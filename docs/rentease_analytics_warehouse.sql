-- The queries in rentease_analytics_mysql.sql, rewritten to run against
-- RENTEASE_ANALYTICS.MARTS instead of production MySQL. Same questions,
-- same answers — zero load on RDS. Grain and logic are unchanged from
-- the originals; only the source tables/joins differ.

-- #######################################################################
-- A. REVENUE & PRICING ANALYTICS
-- #######################################################################

-- A1. Revenue by category, branch, and time period
SELECT
    i.category_name,
    b.branch_name,
    TO_CHAR(f.date_key, 'YYYY-MM') AS month,
    COUNT(DISTINCT f.booking_id) AS bookings,
    SUM(f.total_amount) AS gross_booking_value,
    SUM(CASE WHEN p.payment_type='payment' AND p.payment_status='success' THEN p.amount ELSE 0 END) AS collected_revenue,
    SUM(CASE WHEN p.payment_type='refund' AND p.payment_status='success' THEN p.amount ELSE 0 END) AS refunded_amount
FROM RENTEASE_ANALYTICS.MARTS.FCT_BOOKINGS f
JOIN RENTEASE_ANALYTICS.MARTS.DIM_ITEMS i ON i.item_id = f.item_id
JOIN RENTEASE_ANALYTICS.MARTS.DIM_BRANCHES b ON b.branch_id = f.branch_pickup_id
LEFT JOIN RENTEASE_ANALYTICS.MARTS.FCT_PAYMENTS p ON p.booking_id = f.booking_id
GROUP BY i.category_name, b.branch_name, month
ORDER BY month DESC, collected_revenue DESC;

-- A2. Revenue leakage — bookings that exist but were never fully paid
SELECT
    f.booking_id, f.booking_reference, f.booking_status,
    f.total_amount AS amount_owed,
    COALESCE(SUM(CASE WHEN p.payment_type='payment' AND p.payment_status='success' THEN p.amount ELSE 0 END),0) AS amount_collected,
    f.total_amount - COALESCE(SUM(CASE WHEN p.payment_type='payment' AND p.payment_status='success' THEN p.amount ELSE 0 END),0) AS amount_leaked
FROM RENTEASE_ANALYTICS.MARTS.FCT_BOOKINGS f
LEFT JOIN RENTEASE_ANALYTICS.MARTS.FCT_PAYMENTS p ON p.booking_id = f.booking_id
WHERE f.booking_status IN ('confirmed','active','completed')
GROUP BY f.booking_id, f.booking_reference, f.booking_status, f.total_amount
HAVING amount_leaked > 0
ORDER BY amount_leaked DESC;

-- A3. Refund rate & refund value trend over time, by branch and category
SELECT
    TO_CHAR(p.created_at,'YYYY-MM') AS month,
    i.category_name, b.branch_name,
    COUNT(DISTINCT f.booking_id) AS bookings_with_refund,
    SUM(p.amount) AS total_refunded
FROM RENTEASE_ANALYTICS.MARTS.FCT_PAYMENTS p
JOIN RENTEASE_ANALYTICS.MARTS.FCT_BOOKINGS f ON f.booking_id = p.booking_id
JOIN RENTEASE_ANALYTICS.MARTS.DIM_ITEMS i ON i.item_id = f.item_id
JOIN RENTEASE_ANALYTICS.MARTS.DIM_BRANCHES b ON b.branch_id = f.branch_pickup_id
WHERE p.payment_type='refund' AND p.payment_status='success'
GROUP BY month, i.category_name, b.branch_name
ORDER BY month DESC, total_refunded DESC;

-- A4. Average order value (AOV) by category
SELECT
    i.category_name,
    COUNT(DISTINCT f.booking_id) AS bookings,
    ROUND(AVG(f.total_amount), 2) AS avg_order_value
FROM RENTEASE_ANALYTICS.MARTS.FCT_BOOKINGS f
JOIN RENTEASE_ANALYTICS.MARTS.DIM_ITEMS i ON i.item_id = f.item_id
WHERE f.booking_status IN ('confirmed','active','completed')
GROUP BY i.category_name
ORDER BY avg_order_value DESC;

-- A5. Price elasticity proxy — item price band vs booking frequency
SELECT
    i.category_name,
    CASE
        WHEN i.base_price_daily < 1000 THEN '< 1,000'
        WHEN i.base_price_daily < 3000 THEN '1,000 - 2,999'
        WHEN i.base_price_daily < 6000 THEN '3,000 - 5,999'
        ELSE '6,000+'
    END AS price_band,
    COUNT(DISTINCT i.item_id) AS items_in_band,
    COUNT(f.booking_id) AS total_bookings,
    ROUND(COUNT(f.booking_id) / COUNT(DISTINCT i.item_id), 2) AS bookings_per_item
FROM RENTEASE_ANALYTICS.MARTS.DIM_ITEMS i
LEFT JOIN RENTEASE_ANALYTICS.MARTS.FCT_BOOKINGS f
    ON f.item_id = i.item_id AND f.booking_status IN ('confirmed','active','completed')
GROUP BY i.category_name, price_band
ORDER BY i.category_name, price_band;


-- #######################################################################
-- B. DEMAND & UTILIZATION
-- #######################################################################

-- B1. Item utilization rate (last 90 days)
SELECT
    i.item_id, i.item_name, b.branch_name, i.category_name,
    COALESCE(SUM(DATEDIFF(HOUR, GREATEST(f.start_at, DATEADD(DAY,-90,CURRENT_TIMESTAMP())), LEAST(f.end_at, CURRENT_TIMESTAMP()))/24),0) AS booked_days_last_90,
    ROUND(COALESCE(SUM(DATEDIFF(HOUR, GREATEST(f.start_at, DATEADD(DAY,-90,CURRENT_TIMESTAMP())), LEAST(f.end_at, CURRENT_TIMESTAMP()))/24),0) / 90 * 100, 1) AS utilization_pct
FROM RENTEASE_ANALYTICS.MARTS.DIM_ITEMS i
JOIN RENTEASE_ANALYTICS.MARTS.DIM_BRANCHES b ON b.branch_id = i.branch_id
LEFT JOIN RENTEASE_ANALYTICS.MARTS.FCT_BOOKINGS f
    ON f.item_id = i.item_id AND f.booking_status IN ('confirmed','active','completed')
    AND f.end_at >= DATEADD(DAY,-90,CURRENT_TIMESTAMP())
GROUP BY i.item_id, i.item_name, b.branch_name, i.category_name
ORDER BY utilization_pct ASC;

-- B2. Fleet-level utilization per branch
SELECT
    b.branch_id, b.branch_name,
    COUNT(DISTINCT i.item_id) AS fleet_size,
    COUNT(DISTINCT f.booking_id) AS bookings_last_90,
    ROUND(COUNT(DISTINCT f.booking_id) / COUNT(DISTINCT i.item_id), 2) AS bookings_per_item
FROM RENTEASE_ANALYTICS.MARTS.DIM_BRANCHES b
JOIN RENTEASE_ANALYTICS.MARTS.DIM_ITEMS i ON i.branch_id = b.branch_id
LEFT JOIN RENTEASE_ANALYTICS.MARTS.FCT_BOOKINGS f
    ON f.item_id = i.item_id AND f.booking_status IN ('confirmed','active','completed')
    AND f.date_key >= DATEADD(DAY,-90,CURRENT_DATE())
GROUP BY b.branch_id, b.branch_name
ORDER BY bookings_per_item ASC;

-- B3. Seasonality / demand curves per category
SELECT
    i.category_name,
    TO_CHAR(f.start_at,'YYYY-MM') AS month,
    COUNT(*) AS bookings
FROM RENTEASE_ANALYTICS.MARTS.FCT_BOOKINGS f
JOIN RENTEASE_ANALYTICS.MARTS.DIM_ITEMS i ON i.item_id = f.item_id
WHERE f.booking_status IN ('confirmed','active','completed')
GROUP BY i.category_name, month
ORDER BY i.category_name, month;

-- B4. Booking lead time
SELECT
    i.category_name,
    ROUND(AVG(DATEDIFF(HOUR, f.created_at, f.start_at)/24),1) AS avg_lead_time_days,
    ROUND(MIN(DATEDIFF(HOUR, f.created_at, f.start_at)/24),1) AS min_lead_time_days,
    ROUND(MAX(DATEDIFF(HOUR, f.created_at, f.start_at)/24),1) AS max_lead_time_days
FROM RENTEASE_ANALYTICS.MARTS.FCT_BOOKINGS f
JOIN RENTEASE_ANALYTICS.MARTS.DIM_ITEMS i ON i.item_id = f.item_id
WHERE f.booking_status IN ('confirmed','active','completed')
GROUP BY i.category_name
ORDER BY avg_lead_time_days DESC;


-- #######################################################################
-- C. BOOKING FUNNEL & OPERATIONAL HEALTH
-- #######################################################################

-- C1. Funnel — share of bookings that ever reach each status
SELECT
    new_status,
    COUNT(DISTINCT booking_id) AS bookings_reached,
    ROUND(100.0 * COUNT(DISTINCT booking_id) / (SELECT COUNT(*) FROM RENTEASE_ANALYTICS.MARTS.FCT_BOOKINGS), 1) AS pct_of_all_bookings
FROM RENTEASE_ANALYTICS.MARTS.FCT_BOOKING_STATUS_EVENTS
GROUP BY new_status
ORDER BY DECODE(new_status,'pending',1,'confirmed',2,'active',3,'completed',4,'cancelled',5);

-- C2. Auto-expiry impact — system-expired vs manually cancelled pending bookings
SELECT
    CASE WHEN changed_by IS NULL THEN 'system_auto_expired' ELSE 'manually_cancelled' END AS cancel_reason,
    COUNT(*) AS booking_count
FROM RENTEASE_ANALYTICS.MARTS.FCT_BOOKING_STATUS_EVENTS
WHERE old_status = 'pending' AND new_status = 'cancelled'
GROUP BY cancel_reason;

-- C3. Cancellation rate by category and branch
SELECT
    i.category_name, b.branch_name,
    COUNT(DISTINCT f.booking_id) AS total_bookings,
    COUNT(DISTINCT CASE WHEN f.booking_status = 'cancelled' THEN f.booking_id END) AS cancelled_bookings,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN f.booking_status = 'cancelled' THEN f.booking_id END) / COUNT(DISTINCT f.booking_id), 1) AS cancellation_rate_pct
FROM RENTEASE_ANALYTICS.MARTS.FCT_BOOKINGS f
JOIN RENTEASE_ANALYTICS.MARTS.DIM_ITEMS i ON i.item_id = f.item_id
JOIN RENTEASE_ANALYTICS.MARTS.DIM_BRANCHES b ON b.branch_id = f.branch_pickup_id
GROUP BY i.category_name, b.branch_name
ORDER BY cancellation_rate_pct DESC;

-- C4. Time-to-cancel relative to rental start
SELECT
    f.booking_id, f.booking_reference,
    ROUND(DATEDIFF(HOUR, e.changed_at, f.start_at)/24, 1) AS days_before_start_when_cancelled
FROM RENTEASE_ANALYTICS.MARTS.FCT_BOOKING_STATUS_EVENTS e
JOIN RENTEASE_ANALYTICS.MARTS.FCT_BOOKINGS f ON f.booking_id = e.booking_id
WHERE e.new_status = 'cancelled'
ORDER BY days_before_start_when_cancelled ASC;


-- #######################################################################
-- D. CUSTOMER ANALYTICS
-- #######################################################################

-- D1. Repeat rental rate
SELECT
    COUNT(DISTINCT customer_id) AS customers_with_bookings,
    COUNT(DISTINCT CASE WHEN booking_count > 1 THEN customer_id END) AS repeat_customers,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN booking_count > 1 THEN customer_id END) / COUNT(DISTINCT customer_id), 1) AS repeat_rate_pct
FROM (
    SELECT customer_id, COUNT(*) AS booking_count
    FROM RENTEASE_ANALYTICS.MARTS.FCT_BOOKINGS
    WHERE booking_status = 'completed'
    GROUP BY customer_id
) t;

-- D2. Customer lifetime value (LTV)
SELECT
    u.user_id, u.full_name,
    COUNT(DISTINCT f.booking_id) AS total_bookings,
    SUM(CASE WHEN p.payment_type='payment' AND p.payment_status='success' THEN p.amount ELSE 0 END)
      - SUM(CASE WHEN p.payment_type='refund' AND p.payment_status='success' THEN p.amount ELSE 0 END) AS lifetime_value
FROM RENTEASE_ANALYTICS.MARTS.DIM_USERS u
JOIN RENTEASE_ANALYTICS.MARTS.FCT_BOOKINGS f ON f.customer_id = u.user_id
LEFT JOIN RENTEASE_ANALYTICS.MARTS.FCT_PAYMENTS p ON p.booking_id = f.booking_id
WHERE u.role = 'customer'
GROUP BY u.user_id, u.full_name
ORDER BY lifetime_value DESC;

-- D3. Cohort retention
-- Persisted as a dbt model: RENTEASE_ANALYTICS.MARTS.RPT_CUSTOMER_COHORT_RETENTION
SELECT * FROM RENTEASE_ANALYTICS.MARTS.RPT_CUSTOMER_COHORT_RETENTION
ORDER BY signup_cohort, months_since_signup;

-- D4. Verification status vs completion/cancellation behavior
SELECT
    u.is_verified,
    COUNT(DISTINCT f.booking_id) AS total_bookings,
    COUNT(DISTINCT CASE WHEN f.booking_status='completed' THEN f.booking_id END) AS completed_bookings,
    COUNT(DISTINCT CASE WHEN f.booking_status='cancelled' THEN f.booking_id END) AS cancelled_bookings,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN f.booking_status='completed' THEN f.booking_id END) / COUNT(DISTINCT f.booking_id), 1) AS completion_rate_pct
FROM RENTEASE_ANALYTICS.MARTS.DIM_USERS u
JOIN RENTEASE_ANALYTICS.MARTS.FCT_BOOKINGS f ON f.customer_id = u.user_id
WHERE u.role = 'customer'
GROUP BY u.is_verified;

-- D5. RFM segmentation
-- Persisted as a dbt model: RENTEASE_ANALYTICS.MARTS.RPT_CUSTOMER_RFM
SELECT * FROM RENTEASE_ANALYTICS.MARTS.RPT_CUSTOMER_RFM
ORDER BY monetary_total DESC;


-- #######################################################################
-- E. BRANCH PERFORMANCE
-- #######################################################################

-- E1. Revenue and utilization per branch
SELECT
    b.branch_id, b.branch_name,
    COUNT(DISTINCT i.item_id) AS fleet_size,
    COUNT(DISTINCT f.booking_id) AS total_bookings,
    SUM(CASE WHEN p.payment_type='payment' AND p.payment_status='success' THEN p.amount ELSE 0 END) AS collected_revenue,
    ROUND(COUNT(DISTINCT f.booking_id) / NULLIF(COUNT(DISTINCT i.item_id), 0), 2) AS bookings_per_item
FROM RENTEASE_ANALYTICS.MARTS.DIM_BRANCHES b
LEFT JOIN RENTEASE_ANALYTICS.MARTS.DIM_ITEMS i ON i.branch_id = b.branch_id
LEFT JOIN RENTEASE_ANALYTICS.MARTS.FCT_BOOKINGS f ON f.item_id = i.item_id AND f.booking_status IN ('confirmed','active','completed')
LEFT JOIN RENTEASE_ANALYTICS.MARTS.FCT_PAYMENTS p ON p.booking_id = f.booking_id
GROUP BY b.branch_id, b.branch_name
ORDER BY collected_revenue DESC;

-- E2. Pickup vs. drop-off imbalance per branch
SELECT
    b.branch_id, b.branch_name,
    COUNT(DISTINCT CASE WHEN f.branch_dropoff_id = b.branch_id THEN f.booking_id END) AS units_dropped_off,
    COUNT(DISTINCT CASE WHEN f.branch_pickup_id = b.branch_id THEN f.booking_id END) AS units_picked_up,
    COUNT(DISTINCT CASE WHEN f.branch_dropoff_id = b.branch_id THEN f.booking_id END)
      - COUNT(DISTINCT CASE WHEN f.branch_pickup_id = b.branch_id THEN f.booking_id END) AS net_inflow
FROM RENTEASE_ANALYTICS.MARTS.DIM_BRANCHES b
LEFT JOIN RENTEASE_ANALYTICS.MARTS.FCT_BOOKINGS f
    ON (f.branch_pickup_id = b.branch_id OR f.branch_dropoff_id = b.branch_id) AND f.booking_status = 'completed'
GROUP BY b.branch_id, b.branch_name
ORDER BY net_inflow DESC;


-- #######################################################################
-- F. TRUST & OPERATIONS
-- #######################################################################

-- F1. Admin/staff action volume
SELECT
    u.full_name AS actor_name, u.role AS actor_role, a.action, COUNT(*) AS action_count
FROM RENTEASE_ANALYTICS.MARTS.FCT_AUDIT_EVENTS a
JOIN RENTEASE_ANALYTICS.MARTS.DIM_USERS u ON u.user_id = a.actor_id
GROUP BY u.full_name, u.role, a.action
ORDER BY action_count DESC;

-- F2. After-hours admin activity
SELECT
    u.full_name AS actor_name, a.action, a.entity_type, a.created_at, HOUR(a.created_at) AS action_hour
FROM RENTEASE_ANALYTICS.MARTS.FCT_AUDIT_EVENTS a
JOIN RENTEASE_ANALYTICS.MARTS.DIM_USERS u ON u.user_id = a.actor_id
WHERE u.role IN ('staff','super_admin') AND (HOUR(a.created_at) < 8 OR HOUR(a.created_at) > 20)
ORDER BY a.created_at DESC;

-- F3. Anomalous refund-related admin actions
SELECT
    u.full_name AS actor_name,
    COUNT(*) AS refund_actions,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_all_refund_actions
FROM RENTEASE_ANALYTICS.MARTS.FCT_AUDIT_EVENTS a
JOIN RENTEASE_ANALYTICS.MARTS.DIM_USERS u ON u.user_id = a.actor_id
WHERE a.entity_type = 'payments' AND a.action ILIKE '%refund%'
GROUP BY u.full_name
ORDER BY refund_actions DESC;

-- F4. Payment method failure rate
SELECT
    payment_method,
    COUNT(*) AS total_attempts,
    SUM(CASE WHEN payment_status='failed' THEN 1 ELSE 0 END) AS failed_count,
    ROUND(100.0 * SUM(CASE WHEN payment_status='failed' THEN 1 ELSE 0 END) / COUNT(*), 1) AS failure_rate_pct
FROM RENTEASE_ANALYTICS.MARTS.FCT_PAYMENTS
WHERE payment_type = 'payment'
GROUP BY payment_method
ORDER BY failure_rate_pct DESC;
