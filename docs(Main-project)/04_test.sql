USE rentease;

-- Seed
INSERT INTO categories (name, description) VALUES ('Vehicles', 'Cars and vans');
INSERT INTO branches (name, address, city, phone) VALUES ('Colombo Main', '123 Galle Rd', 'Colombo', '0112345678');
INSERT INTO users (full_name, email, password_hash, role) VALUES
  ('Alice Customer', 'alice@example.com', 'hash1', 'customer'),
  ('Bob Staff', 'bob@example.com', 'hash2', 'staff');
INSERT INTO item_catalog (category_id) VALUES (1);
INSERT INTO items (catalog_id, branch_id, name, base_price_daily, deposit_amount, status)
  VALUES (1, 1, 'Toyota Aqua', 5000.00, 10000.00, 'available');

-- Test 1: normal booking succeeds
CALL sp_create_booking(1, 1, 1, 1, '2026-08-01 09:00:00', '2026-08-03 09:00:00',
                        10000.00, 1500.00, 10000.00, 21500.00, 1, @bid1, @bref1);
SELECT @bid1 AS booking_id, @bref1 AS booking_reference;

-- Test 2: overlapping booking on same item MUST fail
SET @err = NULL;
CALL sp_create_booking(1, 1, 1, 1, '2026-08-02 09:00:00', '2026-08-04 09:00:00',
                        10000.00, 1500.00, 10000.00, 21500.00, 1, @bid2, @bref2);
