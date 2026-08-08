-- =====================================================================
-- RentEase MVP — Dummy/Seed Data
-- Passwords are REAL bcrypt hashes (cost 12) — plaintext listed below
-- so you can actually log in and test. Never do this for real user data.
-- =====================================================================
USE rentease;

SET FOREIGN_KEY_CHECKS = 0; -- remove reference constraints 
TRUNCATE TABLE audit_logs;
TRUNCATE TABLE payments;
TRUNCATE TABLE booking_status_history;
TRUNCATE TABLE bookings;
TRUNCATE TABLE item_photos;
TRUNCATE TABLE items;
TRUNCATE TABLE item_catalog;
TRUNCATE TABLE users;
TRUNCATE TABLE branches;
TRUNCATE TABLE categories;
SET FOREIGN_KEY_CHECKS = 1;

-- ---------------------------------------------------------------------
-- users
--
-- | email                          | password       | role        |
-- |--------------------------------|-----------------|-------------|
-- | super_admin@rentease.com       | SuperAdmin@123  | super_admin |
-- | staff.kasun@rentease.com       | Staff@123       | staff       |
-- | staff.nimali@rentease.com      | Staff@123       | staff       |
-- | alice.perera@example.com       | Customer@123    | customer    |
-- | ruwan.silva@example.com        | Customer@123    | customer    |
-- | dilani.fernando@example.com    | Customer@123    | customer    |
-- | chathura.jay@example.com       | Customer@123    | customer    |
-- ---------------------------------------------------------------------
INSERT INTO users (id, full_name, email, phone, password_hash, role, is_verified, is_active) VALUES
(1, 'System Super Admin',   'super_admin@rentease.com',    '+94770000001', '$2b$12$JfBk.PfRj6CSB8z/DX6DTufqjN9CcKjg1UPn85vzzIeSDzlZ2NEIa', 'super_admin', TRUE,  TRUE),
(2, 'Kasun Perera',         'staff.kasun@rentease.com',    '+94770000002', '$2b$12$1evSt0uX0nOCzv0s0yhPuej2lXdQsJhlez7N5OONMOq69SCpAIpHy', 'staff',       TRUE,  TRUE),
(3, 'Nimali Wickramasinghe','staff.nimali@rentease.com',   '+94770000003', '$2b$12$bTEPQYzTb2P4nkgpwVu8qui7pE6HHkvC4gPgYIzwqAc8sKRnBA6Bq', 'staff',       TRUE,  TRUE),
(4, 'Alice Perera',         'alice.perera@example.com',    '+94770000004', '$2b$12$TQT.9Rf.UURvUjTwmBZMwO1NEzpowAdCiITJAJtN.fPcUwW61Kd/e', 'customer',    TRUE,  TRUE),
(5, 'Ruwan Silva',          'ruwan.silva@example.com',     '+94770000005', '$2b$12$p4yOQ1om7O9/EhklUDUOieNmQlq.ne3XU6sbPATbqhs3fmjLdBy2y', 'customer',    TRUE,  TRUE),
(6, 'Dilani Fernando',      'dilani.fernando@example.com', '+94770000006', '$2b$12$r7n8DZx8XMWWYuL03XG8OOabmUD2jemqbVZZcG6aQ.1AY63PdHisO', 'customer',    FALSE, TRUE),
(7, 'Chathura Jayasuriya',  'chathura.jay@example.com',    '+94770000007', '$2b$12$7B8M9KO9ltbIloSfBh5hc.iwF3bht7JuCikTyJLyHoiFJa1Bf6Nuu', 'customer',    TRUE,  TRUE);

-- ---------------------------------------------------------------------
-- branches
-- ---------------------------------------------------------------------
INSERT INTO branches (id, name, address, city, phone, is_active) VALUES
(1, 'Colombo Main Branch', '123 Galle Road, Colombo 03', 'Colombo', '+94112345678', TRUE),
(2, 'Kandy Branch',        '45 Peradeniya Road, Kandy',  'Kandy',   '+94812345678', TRUE),
(3, 'Galle Branch',        '78 Matara Road, Galle',      'Galle',   '+94912345678', TRUE);

-- ---------------------------------------------------------------------
-- categories
-- ---------------------------------------------------------------------
INSERT INTO categories (id, name, description) VALUES
(1, 'Sedans',      'Compact and mid-size sedans for city driving'),
(2, 'SUVs',        'Sport utility vehicles for family trips and rough terrain'),
(3, 'Vans',        'Passenger and cargo vans'),
(4, 'Motorcycles', 'Scooters and motorcycles for solo riders');

-- ---------------------------------------------------------------------
-- item_catalog (products)
-- ---------------------------------------------------------------------
INSERT INTO item_catalog (id, category_id) VALUES
(1, 1),  -- Toyota Aqua (Sedans)
(2, 1),  -- Honda Civic (Sedans)
(3, 2),  -- Toyota Prado (SUVs)
(4, 3),  -- Toyota Hiace (Vans)
(5, 4);  -- Honda Dio (Motorcycles)

-- ---------------------------------------------------------------------
-- item_photos
-- ---------------------------------------------------------------------
INSERT INTO item_photos (catalog_id, url, sort_order) VALUES
(1, 'https://cdn.rentease.lk/catalog/1/front.jpg', 0),
(1, 'https://cdn.rentease.lk/catalog/1/side.jpg', 1),
(2, 'https://cdn.rentease.lk/catalog/2/front.jpg', 0),
(3, 'https://cdn.rentease.lk/catalog/3/front.jpg', 0),
(3, 'https://cdn.rentease.lk/catalog/3/interior.jpg', 1),
(4, 'https://cdn.rentease.lk/catalog/4/front.jpg', 0),
(5, 'https://cdn.rentease.lk/catalog/5/front.jpg', 0);

-- ---------------------------------------------------------------------
-- items (physical bookable units)
-- ---------------------------------------------------------------------
INSERT INTO items (id, catalog_id, branch_id, name, description, base_price_daily, deposit_amount, status) VALUES
(1, 1, 1, 'Toyota Aqua - CAB-1234',   'Fuel-efficient hybrid hatchback, automatic', 5000.00, 10000.00, 'available'),
(2, 1, 2, 'Toyota Aqua - CAB-5678',   'Fuel-efficient hybrid hatchback, automatic', 5000.00, 10000.00, 'available'),
(3, 2, 1, 'Honda Civic - CAC-1111',   'Comfortable mid-size sedan, automatic',      7000.00, 15000.00, 'available'),
(4, 3, 1, 'Toyota Prado - CAD-2222',  '7-seater SUV, diesel, 4WD',                 15000.00, 30000.00, 'available'),
(5, 3, 3, 'Toyota Prado - CAD-3333',  '7-seater SUV, diesel, 4WD',                 15000.00, 30000.00, 'maintenance'),
(6, 4, 1, 'Toyota Hiace - CAE-4444',  '15-seater passenger van',                   12000.00, 25000.00, 'available'),
(7, 5, 2, 'Honda Dio - BAA-5555',     '110cc scooter, ideal for city commuting',    1500.00,  5000.00, 'available'),
(8, 5, 3, 'Honda Dio - BAA-6666',     '110cc scooter, ideal for city commuting',    1500.00,  5000.00, 'retired');

-- =====================================================================
-- RentEase MVP — Dummy/Seed Data (Part 2: transactional tables)
-- Depends on: 01_schema.sql, 02_dummy_data_core.sql (users, branches,
--             categories, item_catalog, items already populated)
--
-- NOTE ON THE STATUS-HISTORY TRIGGER
-- If `trg_bookings_status_history` is already created on your DB and
-- fires AFTER INSERT on `bookings` (auto-logging the initial status
-- using @rentease_actor_id), then skip the "-- initial pending row"
-- lines inside the booking_status_history INSERT below for each
-- booking — the trigger will have already created them, and inserting
-- again would duplicate the row. If you haven't created that trigger
-- yet, leave everything as-is; this script is self-contained.
-- =====================================================================
USE rentease;

SET FOREIGN_KEY_CHECKS = 0;
TRUNCATE TABLE audit_logs;
TRUNCATE TABLE payments;
TRUNCATE TABLE booking_status_history;
TRUNCATE TABLE bookings;
SET FOREIGN_KEY_CHECKS = 1;

-- ---------------------------------------------------------------------
-- bookings
--
-- | id | ref           | customer         | item                     | status    |
-- |----|---------------|------------------|--------------------------|-----------|
-- | 1  | RE-2026-0001  | Alice Perera     | Toyota Aqua CAB-1234     | completed |
-- | 2  | RE-2026-0002  | Ruwan Silva      | Honda Civic CAC-1111     | confirmed |
-- | 3  | RE-2026-0003  | Dilani Fernando  | Toyota Hiace CAE-4444    | pending   |
-- | 4  | RE-2026-0004  | Chathura Jay.    | Honda Dio BAA-5555       | active    |
-- | 5  | RE-2026-0005  | Alice Perera     | Toyota Prado CAD-2222    | cancelled |
-- | 6  | RE-2026-0006  | Ruwan Silva      | Toyota Aqua CAB-5678     | pending   |
-- ---------------------------------------------------------------------

-- Set actor for trigger-attributed writes (customer self-service booking creation)
INSERT INTO bookings
  (id, booking_reference, customer_id, item_id, branch_pickup_id, branch_dropoff_id,
   start_datetime, end_datetime, status, base_amount, tax_amount, deposit_amount, total_amount)
VALUES
  (1, 'RE-2026-0001', 4, 1, 1, 1, '2026-07-01 09:00:00', '2026-07-05 09:00:00',
   'completed', 20000.00, 2000.00, 10000.00, 22000.00);

INSERT INTO bookings
  (id, booking_reference, customer_id, item_id, branch_pickup_id, branch_dropoff_id,
   start_datetime, end_datetime, status, base_amount, tax_amount, deposit_amount, total_amount)
VALUES
  (2, 'RE-2026-0002', 5, 3, 1, 1, '2026-07-10 10:00:00', '2026-07-12 10:00:00',
   'confirmed', 14000.00, 1400.00, 15000.00, 15400.00);

INSERT INTO bookings
  (id, booking_reference, customer_id, item_id, branch_pickup_id, branch_dropoff_id,
   start_datetime, end_datetime, status, base_amount, tax_amount, deposit_amount, total_amount)
VALUES
  (3, 'RE-2026-0003', 6, 6, 1, 2, '2026-07-15 08:00:00', '2026-07-18 08:00:00',
   'pending', 36000.00, 3600.00, 25000.00, 39600.00);

INSERT INTO bookings
  (id, booking_reference, customer_id, item_id, branch_pickup_id, branch_dropoff_id,
   start_datetime, end_datetime, status, base_amount, tax_amount, deposit_amount, total_amount)
VALUES
  (4, 'RE-2026-0004', 7, 7, 2, 2, '2026-07-20 12:00:00', '2026-07-21 12:00:00',
   'active', 1500.00, 150.00, 5000.00, 1650.00);

INSERT INTO bookings
  (id, booking_reference, customer_id, item_id, branch_pickup_id, branch_dropoff_id,
   start_datetime, end_datetime, status, base_amount, tax_amount, deposit_amount, total_amount)
VALUES
  (5, 'RE-2026-0005', 4, 4, 1, 1, '2026-06-01 09:00:00', '2026-06-05 09:00:00',
   'cancelled', 60000.00, 6000.00, 30000.00, 66000.00);

INSERT INTO bookings
  (id, booking_reference, customer_id, item_id, branch_pickup_id, branch_dropoff_id,
   start_datetime, end_datetime, status, base_amount, tax_amount, deposit_amount, total_amount)
VALUES
  (6, 'RE-2026-0006', 5, 2, 2, 2, '2026-07-25 09:00:00', '2026-07-27 09:00:00',
   'pending', 10000.00, 1000.00, 10000.00, 11000.00);

-- ---------------------------------------------------------------------
-- booking_status_history
-- Skip the first row per booking if trg_bookings_status_history already
-- auto-inserts it on booking creation.
-- ---------------------------------------------------------------------
INSERT INTO booking_status_history (booking_id, old_status, new_status, changed_by, changed_at) VALUES
-- Booking 1: pending -> confirmed -> active -> completed
(1, NULL,        'pending',   4, '2026-06-28 09:00:00'),
(1, 'pending',   'confirmed', 2, '2026-06-28 14:00:00'),
(1, 'confirmed', 'active',    2, '2026-07-01 09:05:00'),
(1, 'active',    'completed', 2, '2026-07-05 09:15:00'),

-- Booking 2: pending -> confirmed
(2, NULL,        'pending',   5, '2026-07-06 11:00:00'),
(2, 'pending',   'confirmed', 3, '2026-07-06 16:00:00'),

-- Booking 3: pending only
(3, NULL,        'pending',   6, '2026-07-12 10:30:00'),

-- Booking 4: pending -> confirmed -> active
(4, NULL,        'pending',   7, '2026-07-18 09:00:00'),
(4, 'pending',   'confirmed', 2, '2026-07-18 13:00:00'),
(4, 'confirmed', 'active',    2, '2026-07-20 12:10:00'),

-- Booking 5: pending -> confirmed -> cancelled
(5, NULL,        'pending',   4, '2026-05-25 09:00:00'),
(5, 'pending',   'confirmed', 2, '2026-05-25 15:00:00'),
(5, 'confirmed', 'cancelled', 2, '2026-05-29 08:00:00'),

-- Booking 6: pending only
(6, NULL,        'pending',   5, '2026-07-21 17:00:00');

-- ---------------------------------------------------------------------
-- payments
-- ---------------------------------------------------------------------
INSERT INTO payments (booking_id, type, amount, method, gateway_reference, status, created_at) VALUES
-- Booking 1 (completed): full payment, then deposit refunded after return
(1, 'payment', 22000.00, 'card',          'PG-TXN-100001', 'success', '2026-06-28 14:05:00'),
(1, 'refund',  10000.00, 'card',          'PG-RFD-100001', 'success', '2026-07-05 09:20:00'),

-- Booking 2 (confirmed): full payment taken up front
(2, 'payment', 15400.00, 'card',          'PG-TXN-100002', 'success', '2026-07-06 16:05:00'),

-- Booking 3 (pending): payment attempt not yet completed
(3, 'payment', 39600.00, 'bank_transfer', NULL,             'pending', '2026-07-12 10:35:00'),

-- Booking 4 (active): cash payment on pickup
(4, 'payment', 1650.00,  'cash',          NULL,             'success', '2026-07-20 12:15:00'),

-- Booking 5 (cancelled): original payment, then refund minus forfeited deposit
(5, 'payment', 66000.00, 'card',          'PG-TXN-100005', 'success', '2026-05-25 15:05:00'),
(5, 'refund',  60000.00, 'card',          'PG-RFD-100005', 'success', '2026-05-29 08:10:00'),

-- Booking 6 (pending): payment initiated, awaiting confirmation
(6, 'payment', 11000.00, 'bank_transfer', NULL,             'pending', '2026-07-21 17:05:00');

-- ---------------------------------------------------------------------
-- audit_logs
-- ---------------------------------------------------------------------
INSERT INTO audit_logs (actor_id, action, entity_type, entity_id, created_at) VALUES
(4, 'booking_created',       'booking', 1, '2026-06-28 09:00:00'),
(2, 'booking_status_change', 'booking', 1, '2026-06-28 14:00:00'),
(2, 'payment_recorded',      'payment', 1, '2026-06-28 14:05:00'),
(2, 'item_status_change',    'item',    5, '2026-05-20 10:00:00'),
(2, 'item_status_change',    'item',    8, '2026-05-22 11:00:00'),
(3, 'customer.registered',   'customer',6, '2026-07-11 08:05:00'),
(2, 'user_verified',         'user',    7, '2026-06-15 12:10:00'),
(NULL, 'system_cleanup',     'booking', 5, '2026-05-30 02:00:00');
