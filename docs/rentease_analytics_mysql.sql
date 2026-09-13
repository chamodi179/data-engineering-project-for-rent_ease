-- Used MY SQL Production DB to analyse revenue, demand, and operational health of the rental business.

-- #######################################################################
-- A. REVENUE & PRICING ANALYTICS
-- #######################################################################

-- A1. Revenue by category, branch, and time period
SELECT
    c.name                          AS category_name,
    br.name                         AS branch_name,
    DATE_FORMAT(bk.created_at,'%Y-%m') AS month,
    COUNT(DISTINCT bk.id)           AS bookings,
    SUM(bk.total_amount)            AS gross_booking_value,
    SUM(CASE WHEN p.type='payment' AND p.status='success' THEN p.amount ELSE 0 END) AS collected_revenue,
    SUM(CASE WHEN p.type='refund'  AND p.status='success' THEN p.amount ELSE 0 END) AS refunded_amount
FROM bookings bk
JOIN items i        ON i.id = bk.item_id
JOIN item_catalog ic ON ic.id = i.catalog_id
JOIN categories c    ON c.id = ic.category_id
JOIN branches br     ON br.id = bk.branch_pickup_id
LEFT JOIN payments p ON p.booking_id = bk.id
GROUP BY c.name, br.name, month
ORDER BY month DESC, collected_revenue DESC;

-- A2. Revenue leakage — bookings that exist but were never fully paid
-- (base_amount/total_amount vs what actually landed in payments)
SELECT
    bk.id                    AS booking_id,
    bk.booking_reference,
    bk.status                AS booking_status,
    bk.total_amount          AS amount_owed,
    COALESCE(SUM(CASE WHEN p.type='payment' AND p.status='success' THEN p.amount ELSE 0 END), 0) AS amount_collected,
    bk.total_amount - COALESCE(SUM(CASE WHEN p.type='payment' AND p.status='success' THEN p.amount ELSE 0 END), 0) AS amount_leaked
FROM bookings bk
LEFT JOIN payments p ON p.booking_id = bk.id
WHERE bk.status IN ('confirmed','active','completed')   -- booking is "real", not abandoned
GROUP BY bk.id, bk.booking_reference, bk.status, bk.total_amount
HAVING amount_leaked > 0
ORDER BY amount_leaked DESC;

-- A3. Refund rate & refund value trend over time, by branch and category
SELECT
    DATE_FORMAT(p.created_at,'%Y-%m')  AS month,
    c.name                              AS category_name,
    br.name                             AS branch_name,
    COUNT(DISTINCT bk.id)               AS bookings_with_refund,
    SUM(p.amount)                       AS total_refunded
FROM payments p
JOIN bookings bk      ON bk.id = p.booking_id
JOIN items i           ON i.id = bk.item_id
JOIN item_catalog ic    ON ic.id = i.catalog_id
JOIN categories c        ON c.id = ic.category_id
JOIN branches br          ON br.id = bk.branch_pickup_id
WHERE p.type = 'refund' AND p.status = 'success'
GROUP BY month, c.name, br.name
ORDER BY month DESC, total_refunded DESC;

-- A4. Average order value (AOV) by category
SELECT
    c.name                    AS category_name,
    COUNT(DISTINCT bk.id)     AS bookings,
    ROUND(AVG(bk.total_amount), 2) AS avg_order_value
FROM bookings bk
JOIN items i        ON i.id = bk.item_id
JOIN item_catalog ic ON ic.id = i.catalog_id
JOIN categories c    ON c.id = ic.category_id
WHERE bk.status IN ('confirmed','active','completed')
GROUP BY c.name
ORDER BY avg_order_value DESC;

-- A5. Price elasticity proxy — does base_price_daily correlate with
-- booking frequency within a category? (bucket items by price band)
SELECT
    c.name                                          AS category_name,
    CASE
        WHEN i.base_price_daily < 1000 THEN '< 1,000'
        WHEN i.base_price_daily < 3000 THEN '1,000 - 2,999'
        WHEN i.base_price_daily < 6000 THEN '3,000 - 5,999'
        ELSE '6,000+'
    END                                              AS price_band,
    COUNT(DISTINCT i.id)                             AS items_in_band,
    COUNT(bk.id)                                     AS total_bookings,
    ROUND(COUNT(bk.id) / COUNT(DISTINCT i.id), 2)    AS bookings_per_item
FROM items i
JOIN item_catalog ic ON ic.id = i.catalog_id
JOIN categories c     ON c.id = ic.category_id
LEFT JOIN bookings bk  ON bk.item_id = i.id AND bk.status IN ('confirmed','active','completed')
GROUP BY c.name, price_band
ORDER BY c.name, price_band;


-- #######################################################################
-- B. DEMAND & UTILIZATION
-- #######################################################################

-- B1. Item utilization rate (last 90 days) — booked days / available days
SELECT
    i.id                                   AS item_id,
    i.name                                 AS item_name,
    b.name                                 AS branch_name,
    c.name                                 AS category_name,
    COALESCE(SUM(
        TIMESTAMPDIFF(HOUR,
            GREATEST(bk.start_datetime, NOW() - INTERVAL 90 DAY),
            LEAST(bk.end_datetime, NOW())
        ) / 24
    ), 0)                                   AS booked_days_last_90,
    ROUND(
        COALESCE(SUM(
            TIMESTAMPDIFF(HOUR,
                GREATEST(bk.start_datetime, NOW() - INTERVAL 90 DAY),
                LEAST(bk.end_datetime, NOW())
            ) / 24
        ), 0) / 90 * 100, 1
    )                                       AS utilization_pct
FROM items i
JOIN branches b        ON b.id = i.branch_id
JOIN item_catalog ic    ON ic.id = i.catalog_id
JOIN categories c        ON c.id = ic.category_id
LEFT JOIN bookings bk     ON bk.item_id = i.id
                          AND bk.status IN ('confirmed','active','completed')
                          AND bk.end_datetime >= NOW() - INTERVAL 90 DAY
GROUP BY i.id, i.name, b.name, c.name
ORDER BY utilization_pct ASC;

-- B2. Fleet-level utilization per branch — which branches are
-- over/under-stocked relative to demand
SELECT
    br.id                              AS branch_id,
    br.name                            AS branch_name,
    COUNT(DISTINCT i.id)               AS fleet_size,
    COUNT(DISTINCT bk.id)              AS bookings_last_90,
    ROUND(COUNT(DISTINCT bk.id) / COUNT(DISTINCT i.id), 2) AS bookings_per_item
FROM branches br
JOIN items i        ON i.branch_id = br.id
LEFT JOIN bookings bk ON bk.item_id = i.id
                       AND bk.status IN ('confirmed','active','completed')
                       AND bk.created_at >= NOW() - INTERVAL 90 DAY
GROUP BY br.id, br.name
ORDER BY bookings_per_item ASC;   -- lowest = understocked relative to fleet, or overstocked & idle

-- B3. Seasonality / demand curves per category (monthly booking volume)
SELECT
    c.name                              AS category_name,
    DATE_FORMAT(bk.start_datetime,'%Y-%m') AS month,
    COUNT(*)                            AS bookings
FROM bookings bk
JOIN items i        ON i.id = bk.item_id
JOIN item_catalog ic ON ic.id = i.catalog_id
JOIN categories c    ON c.id = ic.category_id
WHERE bk.status IN ('confirmed','active','completed')
GROUP BY c.name, month
ORDER BY c.name, month;

-- B4. Booking lead time — how far ahead customers book (created_at vs start_datetime)
SELECT
    c.name                                                    AS category_name,
    ROUND(AVG(TIMESTAMPDIFF(HOUR, bk.created_at, bk.start_datetime) / 24), 1) AS avg_lead_time_days,
    ROUND(MIN(TIMESTAMPDIFF(HOUR, bk.created_at, bk.start_datetime) / 24), 1) AS min_lead_time_days,
    ROUND(MAX(TIMESTAMPDIFF(HOUR, bk.created_at, bk.start_datetime) / 24), 1) AS max_lead_time_days
FROM bookings bk
JOIN items i        ON i.id = bk.item_id
JOIN item_catalog ic ON ic.id = i.catalog_id
JOIN categories c    ON c.id = ic.category_id
WHERE bk.status IN ('confirmed','active','completed')
GROUP BY c.name
ORDER BY avg_lead_time_days DESC;


-- #######################################################################
-- C. BOOKING FUNNEL & OPERATIONAL HEALTH
-- #######################################################################

-- C1. Funnel — share of bookings that ever reach each status
SELECT
    new_status,
    COUNT(DISTINCT booking_id)                                     AS bookings_reached,
    ROUND(100.0 * COUNT(DISTINCT booking_id) /
        (SELECT COUNT(*) FROM bookings), 1)                        AS pct_of_all_bookings
FROM booking_status_history
GROUP BY new_status
ORDER BY FIELD(new_status, 'pending','confirmed','active','completed','cancelled');

-- C2. Auto-expiry impact — system-expired vs manually cancelled pending bookings
SELECT
    CASE WHEN changed_by IS NULL THEN 'system_auto_expired' ELSE 'manually_cancelled' END AS cancel_reason,
    COUNT(*) AS booking_count
FROM booking_status_history
WHERE old_status = 'pending' AND new_status = 'cancelled'
GROUP BY cancel_reason;

-- C3. Cancellation rate by category and branch
SELECT
    c.name                                                              AS category_name,
    br.name                                                             AS branch_name,
    COUNT(DISTINCT bk.id)                                               AS total_bookings,
    COUNT(DISTINCT CASE WHEN bk.status = 'cancelled' THEN bk.id END)    AS cancelled_bookings,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN bk.status = 'cancelled' THEN bk.id END)
        / COUNT(DISTINCT bk.id), 1)                                     AS cancellation_rate_pct
FROM bookings bk
JOIN items i        ON i.id = bk.item_id
JOIN item_catalog ic ON ic.id = i.catalog_id
JOIN categories c    ON c.id = ic.category_id
JOIN branches br     ON br.id = bk.branch_pickup_id
GROUP BY c.name, br.name
ORDER BY cancellation_rate_pct DESC;

-- C4. Time-to-cancel relative to rental start_datetime
-- (how close to the rental date do people cancel — relevant given the
-- time-gated cancellation/refund policy)
SELECT
    bk.id                                                              AS booking_id,
    bk.booking_reference,
    ROUND(TIMESTAMPDIFF(HOUR, bsh.changed_at, bk.start_datetime) / 24, 1) AS days_before_start_when_cancelled
FROM booking_status_history bsh
JOIN bookings bk ON bk.id = bsh.booking_id
WHERE bsh.new_status = 'cancelled'
ORDER BY days_before_start_when_cancelled ASC;   -- smallest = last-minute cancellations


-- #######################################################################
-- D. CUSTOMER ANALYTICS
-- #######################################################################

-- D1. Repeat rental rate — share of customers with more than one completed booking
SELECT
    COUNT(DISTINCT customer_id)                                                    AS customers_with_bookings,
    COUNT(DISTINCT CASE WHEN booking_count > 1 THEN customer_id END)                AS repeat_customers,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN booking_count > 1 THEN customer_id END)
        / COUNT(DISTINCT customer_id), 1)                                          AS repeat_rate_pct
FROM (
    SELECT customer_id, COUNT(*) AS booking_count
    FROM bookings
    WHERE status = 'completed'
    GROUP BY customer_id
) AS per_customer;

-- D2. Customer lifetime value (LTV) — total collected revenue per customer
SELECT
    u.id                                     AS customer_id,
    u.full_name,
    COUNT(DISTINCT bk.id)                    AS total_bookings,
    SUM(CASE WHEN p.type='payment' AND p.status='success' THEN p.amount ELSE 0 END)
      - SUM(CASE WHEN p.type='refund' AND p.status='success' THEN p.amount ELSE 0 END) AS lifetime_value
FROM users u
JOIN bookings bk  ON bk.customer_id = u.id
LEFT JOIN payments p ON p.booking_id = bk.id
WHERE u.role = 'customer'
GROUP BY u.id, u.full_name
ORDER BY lifetime_value DESC;

-- D3. Cohort retention — group customers by signup month, track what
-- % of each cohort books again in subsequent months
SELECT
    DATE_FORMAT(u.created_at,'%Y-%m')      AS signup_cohort,
    DATE_FORMAT(bk.created_at,'%Y-%m')      AS booking_month,
    PERIOD_DIFF(
        DATE_FORMAT(bk.created_at,'%Y%m'),
        DATE_FORMAT(u.created_at,'%Y%m')
    )                                        AS months_since_signup,
    COUNT(DISTINCT bk.customer_id)          AS active_customers
FROM users u
JOIN bookings bk ON bk.customer_id = u.id
WHERE u.role = 'customer'
GROUP BY signup_cohort, booking_month, months_since_signup
ORDER BY signup_cohort, months_since_signup;

-- D4. Verification status vs. completion/cancellation behavior
SELECT
    u.is_verified,
    COUNT(DISTINCT bk.id)                                                AS total_bookings,
    COUNT(DISTINCT CASE WHEN bk.status='completed'  THEN bk.id END)     AS completed_bookings,
    COUNT(DISTINCT CASE WHEN bk.status='cancelled'  THEN bk.id END)     AS cancelled_bookings,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN bk.status='completed' THEN bk.id END)
        / COUNT(DISTINCT bk.id), 1)                                     AS completion_rate_pct
FROM users u
JOIN bookings bk ON bk.customer_id = u.id
WHERE u.role = 'customer'
GROUP BY u.is_verified;

-- D5. RFM segmentation (Recency, Frequency, Monetary)
SELECT
    u.id                                            AS customer_id,
    u.full_name,
    DATEDIFF(NOW(), MAX(bk.created_at))              AS recency_days,
    COUNT(DISTINCT bk.id)                            AS frequency_bookings,
    SUM(bk.total_amount)                             AS monetary_total,
    NTILE(5) OVER (ORDER BY DATEDIFF(NOW(), MAX(bk.created_at)) ASC)  AS recency_score,
    NTILE(5) OVER (ORDER BY COUNT(DISTINCT bk.id) DESC)               AS frequency_score,
    NTILE(5) OVER (ORDER BY SUM(bk.total_amount) DESC)                AS monetary_score
FROM users u
JOIN bookings bk ON bk.customer_id = u.id
WHERE u.role = 'customer'
  AND bk.status IN ('confirmed','active','completed')
GROUP BY u.id, u.full_name
ORDER BY monetary_total DESC;


-- #######################################################################
-- E. BRANCH PERFORMANCE
-- #######################################################################

-- E1. Revenue and utilization per branch, side by side
SELECT
    br.id                                     AS branch_id,
    br.name                                   AS branch_name,
    COUNT(DISTINCT i.id)                      AS fleet_size,
    COUNT(DISTINCT bk.id)                     AS total_bookings,
    SUM(CASE WHEN p.type='payment' AND p.status='success' THEN p.amount ELSE 0 END) AS collected_revenue,
    ROUND(COUNT(DISTINCT bk.id) / NULLIF(COUNT(DISTINCT i.id), 0), 2)   AS bookings_per_item
FROM branches br
LEFT JOIN items i     ON i.branch_id = br.id
LEFT JOIN bookings bk  ON bk.item_id = i.id AND bk.status IN ('confirmed','active','completed')
LEFT JOIN payments p    ON p.booking_id = bk.id
GROUP BY br.id, br.name
ORDER BY collected_revenue DESC;

-- E2. Pickup vs. drop-off imbalance per branch — fleet drift signal
SELECT
    br.id   AS branch_id,
    br.name AS branch_name,
    COUNT(DISTINCT CASE WHEN bk.branch_dropoff_id = br.id THEN bk.id END) AS units_dropped_off,
    COUNT(DISTINCT CASE WHEN bk.branch_pickup_id  = br.id THEN bk.id END) AS units_picked_up,
    COUNT(DISTINCT CASE WHEN bk.branch_dropoff_id = br.id THEN bk.id END)
      - COUNT(DISTINCT CASE WHEN bk.branch_pickup_id = br.id THEN bk.id END) AS net_inflow
FROM branches br
LEFT JOIN bookings bk
    ON (bk.branch_pickup_id = br.id OR bk.branch_dropoff_id = br.id)
    AND bk.status = 'completed'
GROUP BY br.id, br.name
ORDER BY net_inflow DESC;


-- #######################################################################
-- F. TRUST & OPERATIONS
-- #######################################################################

-- F1. Admin/staff action volume from audit_logs
SELECT
    u.full_name                    AS actor_name,
    u.role                         AS actor_role,
    al.action,
    COUNT(*)                       AS action_count
FROM audit_logs al
JOIN users u ON u.id = al.actor_id
GROUP BY u.full_name, u.role, al.action
ORDER BY action_count DESC;

-- F2. After-hours admin activity — actions outside typical business hours
-- (adjust the hour range to your actual operating hours)
SELECT
    u.full_name                    AS actor_name,
    al.action,
    al.entity_type,
    al.created_at,
    HOUR(al.created_at)            AS action_hour
FROM audit_logs al
JOIN users u ON u.id = al.actor_id
WHERE u.role IN ('staff','super_admin')
  AND (HOUR(al.created_at) < 8 OR HOUR(al.created_at) > 20)
ORDER BY al.created_at DESC;

-- F3. Anomalous refund-related admin actions — refund actions per admin,
-- flag actors issuing unusually many refunds relative to peers
SELECT
    u.full_name                    AS actor_name,
    COUNT(*)                       AS refund_actions,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_all_refund_actions
FROM audit_logs al
JOIN users u ON u.id = al.actor_id
WHERE al.entity_type = 'payments'
  AND al.action LIKE '%refund%'
GROUP BY u.full_name
ORDER BY refund_actions DESC;

-- F4. Payment method failure rate — is card declining more than others
SELECT
    method,
    COUNT(*)                                                        AS total_attempts,
    SUM(CASE WHEN status='failed'  THEN 1 ELSE 0 END)                AS failed_count,
    ROUND(100.0 * SUM(CASE WHEN status='failed' THEN 1 ELSE 0 END)
        / COUNT(*), 1)                                               AS failure_rate_pct
FROM payments
WHERE type = 'payment'
GROUP BY method
ORDER BY failure_rate_pct DESC;