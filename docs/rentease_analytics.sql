-- =====================================================================
-- RentEase Analytics Layer
-- Part 1: Star schema (fact/dim) for BI tools (Metabase, Superset, PBI)
-- Part 2: Analytical queries runnable directly against the OLTP schema
--         (01_schema.sql) for teams not yet running a warehouse
-- =====================================================================


-- =====================================================================
-- PART 1 — STAR SCHEMA
-- Grain: fact_bookings = one row per booking
--        fact_payments = one row per payment/refund event
-- Designed to be populated via CDC (Debezium/Kafka/Spark) or nightly ETL
-- from the OLTP tables in 01_schema.sql.
-- =====================================================================

CREATE DATABASE IF NOT EXISTS rentease_analytics
    CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE rentease_analytics;

-- ---------------------------------------------------------------------
-- dim_date — standard date dimension, one row per calendar day
-- ---------------------------------------------------------------------
CREATE TABLE dim_date (
    date_key        INT PRIMARY KEY,          -- YYYYMMDD
    full_date       DATE NOT NULL,
    day_of_week     TINYINT NOT NULL,          -- 1=Mon .. 7=Sun
    day_name        VARCHAR(10) NOT NULL,
    week_of_year    TINYINT NOT NULL,
    month_num       TINYINT NOT NULL,
    month_name      VARCHAR(10) NOT NULL,
    quarter         TINYINT NOT NULL,
    year            SMALLINT NOT NULL,
    is_weekend      BOOLEAN NOT NULL
);

-- ---------------------------------------------------------------------
-- dim_customer — SCD-2 so customer segment/verification changes are
-- traceable over time (role can change customer -> staff, etc.)
-- ---------------------------------------------------------------------
CREATE TABLE dim_customer (
    customer_sk     BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    customer_id     BIGINT UNSIGNED NOT NULL,   -- natural key = users.id
    full_name       VARCHAR(150) NOT NULL,
    email           VARCHAR(255) NOT NULL,
    role            ENUM('customer','staff','super_admin') NOT NULL,
    is_verified     BOOLEAN NOT NULL,
    signup_date     DATE NOT NULL,
    valid_from      TIMESTAMP NOT NULL,
    valid_to        TIMESTAMP NULL,             -- NULL = current row
    is_current      BOOLEAN NOT NULL DEFAULT TRUE,
    INDEX idx_dim_customer_natural (customer_id, is_current)
);

-- ---------------------------------------------------------------------
-- dim_branch
-- ---------------------------------------------------------------------
CREATE TABLE dim_branch (
    branch_sk       BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    branch_id       BIGINT UNSIGNED NOT NULL,   -- natural key = branches.id
    name            VARCHAR(150) NOT NULL,
    city            VARCHAR(100) NOT NULL,
    is_active       BOOLEAN NOT NULL,
    INDEX idx_dim_branch_natural (branch_id)
);

-- ---------------------------------------------------------------------
-- dim_category
-- ---------------------------------------------------------------------
CREATE TABLE dim_category (
    category_sk     BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    category_id     BIGINT UNSIGNED NOT NULL,   -- natural key = categories.id
    name            VARCHAR(100) NOT NULL,
    INDEX idx_dim_category_natural (category_id)
);

-- ---------------------------------------------------------------------
-- dim_item — one row per physical bookable unit (items table),
-- carries catalog + category context denormalized for fast filtering
-- ---------------------------------------------------------------------
CREATE TABLE dim_item (
    item_sk         BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    item_id         BIGINT UNSIGNED NOT NULL,   -- natural key = items.id
    catalog_id      BIGINT UNSIGNED NOT NULL,
    category_sk     BIGINT UNSIGNED NOT NULL,
    home_branch_sk  BIGINT UNSIGNED NOT NULL,
    item_name       VARCHAR(150) NOT NULL,
    base_price_daily DECIMAL(10,2) NOT NULL,
    deposit_amount  DECIMAL(10,2) NOT NULL,
    current_status  ENUM('available','rented','maintenance','retired') NOT NULL,
    INDEX idx_dim_item_natural (item_id),
    CONSTRAINT fk_dim_item_category FOREIGN KEY (category_sk) REFERENCES dim_category(category_sk),
    CONSTRAINT fk_dim_item_branch   FOREIGN KEY (home_branch_sk) REFERENCES dim_branch(branch_sk)
);

-- ---------------------------------------------------------------------
-- fact_bookings — grain: one row per booking
-- ---------------------------------------------------------------------
CREATE TABLE fact_bookings (
    booking_sk          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    booking_id          BIGINT UNSIGNED NOT NULL,   -- natural key = bookings.id
    booking_reference   VARCHAR(30) NOT NULL,

    customer_sk         BIGINT UNSIGNED NOT NULL,
    item_sk              BIGINT UNSIGNED NOT NULL,
    category_sk          BIGINT UNSIGNED NOT NULL,
    pickup_branch_sk     BIGINT UNSIGNED NOT NULL,
    dropoff_branch_sk    BIGINT UNSIGNED NOT NULL,

    created_date_key     INT NOT NULL,               -- FK dim_date, booking creation
    start_date_key       INT NOT NULL,                -- FK dim_date, rental start
    end_date_key          INT NOT NULL,               -- FK dim_date, rental end

    start_datetime        DATETIME NOT NULL,
    end_datetime           DATETIME NOT NULL,
    rental_days            DECIMAL(6,2) NOT NULL,      -- (end - start) in days
    lead_time_days         DECIMAL(6,2) NOT NULL,      -- start_date - created_date

    final_status            ENUM('pending','confirmed','active','completed','cancelled') NOT NULL,
    was_auto_expired         BOOLEAN NOT NULL DEFAULT FALSE,  -- expired by Celery beat, not user

    base_amount              DECIMAL(10,2) NOT NULL,
    tax_amount                DECIMAL(10,2) NOT NULL,
    deposit_amount             DECIMAL(10,2) NOT NULL,
    total_amount                DECIMAL(10,2) NOT NULL,

    is_same_branch_dropoff       BOOLEAN NOT NULL,   -- pickup_branch = dropoff_branch

    INDEX idx_fact_bookings_natural (booking_id),
    INDEX idx_fact_bookings_customer (customer_sk),
    INDEX idx_fact_bookings_item (item_sk),
    INDEX idx_fact_bookings_dates (start_date_key, end_date_key)
);

-- ---------------------------------------------------------------------
-- fact_payments — grain: one row per payment/refund event
-- ---------------------------------------------------------------------
CREATE TABLE fact_payments (
    payment_sk       BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    payment_id       BIGINT UNSIGNED NOT NULL,    -- natural key = payments.id
    booking_sk       BIGINT UNSIGNED NOT NULL,
    date_key         INT NOT NULL,                -- FK dim_date, payment created_at
    type             ENUM('payment','refund') NOT NULL,
    method           ENUM('card','cash','bank_transfer') NOT NULL,
    status           ENUM('pending','success','failed') NOT NULL,
    amount           DECIMAL(10,2) NOT NULL,
    signed_amount    DECIMAL(10,2) NOT NULL,      -- +amount for payment, -amount for refund

    INDEX idx_fact_payments_booking (booking_sk),
    INDEX idx_fact_payments_date (date_key),
    CONSTRAINT fk_fact_payments_booking FOREIGN KEY (booking_sk) REFERENCES fact_bookings(booking_sk)
);


-- =====================================================================
-- PART 2 — ANALYTICAL QUERIES AGAINST THE OLTP SCHEMA (01_schema.sql)
-- Runnable today, no warehouse required. Good for a first dashboard
-- pass before the star schema above is built out.
-- =====================================================================

-- -----------------------------------------------------------------
-- 2.1 Item utilization rate (last 90 days)
-- booked days / available days per item — flags idle fleet
-- -----------------------------------------------------------------
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
ORDER BY utilization_pct ASC;   -- lowest utilization first = idle fleet


-- -----------------------------------------------------------------
-- 2.2 Booking funnel drop-off (all-time)
-- What share of bookings ever reach each status, and how many were
-- auto-expired (never confirmed) vs actively cancelled by someone
-- -----------------------------------------------------------------
SELECT
    new_status,
    COUNT(DISTINCT booking_id)                                     AS bookings_reached,
    ROUND(100.0 * COUNT(DISTINCT booking_id) /
        (SELECT COUNT(*) FROM bookings), 1)                        AS pct_of_all_bookings
FROM booking_status_history
GROUP BY new_status
ORDER BY FIELD(new_status, 'pending','confirmed','active','completed','cancelled');

-- Auto-expired vs. manually cancelled pending bookings
SELECT
    CASE WHEN changed_by IS NULL THEN 'system_auto_expired' ELSE 'manually_cancelled' END AS cancel_reason,
    COUNT(*) AS booking_count
FROM booking_status_history
WHERE old_status = 'pending' AND new_status = 'cancelled'
GROUP BY cancel_reason;


-- -----------------------------------------------------------------
-- 2.3 Revenue by category & branch (current month)
-- -----------------------------------------------------------------
SELECT
    c.name                          AS category_name,
    br.name                         AS branch_name,
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
WHERE bk.created_at >= DATE_FORMAT(NOW(), '%Y-%m-01')
GROUP BY c.name, br.name
ORDER BY collected_revenue DESC;


-- -----------------------------------------------------------------
-- 2.4 Refund rate by category — trust/quality signal
-- -----------------------------------------------------------------
SELECT
    c.name AS category_name,
    COUNT(DISTINCT bk.id)                                                  AS total_bookings,
    COUNT(DISTINCT CASE WHEN p.type='refund' THEN bk.id END)               AS bookings_with_refund,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN p.type='refund' THEN bk.id END)
        / NULLIF(COUNT(DISTINCT bk.id), 0), 1)                             AS refund_rate_pct
FROM bookings bk
JOIN items i         ON i.id = bk.item_id
JOIN item_catalog ic  ON ic.id = i.catalog_id
JOIN categories c      ON c.id = ic.category_id
LEFT JOIN payments p    ON p.booking_id = bk.id AND p.status = 'success'
GROUP BY c.name
ORDER BY refund_rate_pct DESC;


-- -----------------------------------------------------------------
-- 2.5 Pickup vs. drop-off imbalance per branch — fleet drift signal
-- Positive net_inflow = branch is accumulating units;
-- negative = branch is bleeding fleet to other branches
-- -----------------------------------------------------------------
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


-- -----------------------------------------------------------------
-- 2.6 Customer RFM segmentation (Recency, Frequency, Monetary)
-- -----------------------------------------------------------------
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


-- -----------------------------------------------------------------
-- 2.7 Payment method failure rate — payments ops signal
-- -----------------------------------------------------------------
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