-- =====================================================================
-- RentEase MVP — Stored Procedures
-- =====================================================================
USE rentease;

DELIMITER $$

-- ---------------------------------------------------------------------
-- sp_create_booking
--
-- Creates a booking while guaranteeing no double-booking, even under
-- concurrent requests for the same item and overlapping dates.
--
-- Strategy:
--   1. SELECT ... FOR UPDATE on the target `items` row. This turns the
--      item into a per-item mutex: any two transactions trying to book
--      the same item are serialized against each other, closing the
--      classic "two people click Book at the same instant" race that a
--      plain SELECT-then-INSERT can't prevent.
--   2. With that lock held, check for overlapping bookings in
--      (pending, confirmed, active). If one exists, roll back and
--      signal an error.
--   3. Otherwise insert the booking. The AFTER INSERT trigger records
--      the initial status into booking_status_history automatically.
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_create_booking $$

CREATE PROCEDURE sp_create_booking (
    IN  p_customer_id       BIGINT UNSIGNED,
    IN  p_item_id           BIGINT UNSIGNED,
    IN  p_branch_pickup_id  BIGINT UNSIGNED,
    IN  p_branch_dropoff_id BIGINT UNSIGNED,
    IN  p_start_datetime    DATETIME,
    IN  p_end_datetime      DATETIME,
    IN  p_base_amount       DECIMAL(10,2),
    IN  p_tax_amount        DECIMAL(10,2),
    IN  p_deposit_amount    DECIMAL(10,2),
    IN  p_total_amount      DECIMAL(10,2),
    IN  p_actor_id          BIGINT UNSIGNED,
    OUT p_booking_id        BIGINT UNSIGNED,
    OUT p_booking_reference VARCHAR(30)
)
this_proc: BEGIN
    DECLARE v_conflict_count INT DEFAULT 0;
    DECLARE v_item_exists    INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    IF p_end_datetime <= p_start_datetime THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'end_datetime must be after start_datetime';
    END IF;

    START TRANSACTION;

    -- Lock the item row: serializes concurrent booking attempts on it.
    SELECT COUNT(*) INTO v_item_exists
    FROM items
    WHERE id = p_item_id
      AND status = 'available'
    FOR UPDATE;

    IF v_item_exists = 0 THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Item does not exist or is not available for booking';
    END IF;

    -- With the item locked, check for any overlapping active booking.
    SELECT COUNT(*) INTO v_conflict_count
    FROM bookings
    WHERE item_id = p_item_id
      AND status IN ('pending', 'confirmed', 'active')
      AND start_datetime < p_end_datetime
      AND end_datetime   > p_start_datetime
    FOR UPDATE;

    IF v_conflict_count > 0 THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Item is already booked for the requested date range';
    END IF;

    SET p_booking_reference = CONCAT(
        'RE-', DATE_FORMAT(NOW(), '%Y%m%d'), '-',
        LPAD(FLOOR(RAND() * 999999), 6, '0')
    );

    -- Let the trigger know who's making this change.
    SET @rentease_actor_id = p_actor_id;

    INSERT INTO bookings (
        booking_reference, customer_id, item_id,
        branch_pickup_id, branch_dropoff_id,
        start_datetime, end_datetime, status,
        base_amount, tax_amount, deposit_amount, total_amount
    ) VALUES (
        p_booking_reference, p_customer_id, p_item_id,
        p_branch_pickup_id, p_branch_dropoff_id,
        p_start_datetime, p_end_datetime, 'pending',
        p_base_amount, p_tax_amount, p_deposit_amount, p_total_amount
    );

    SET p_booking_id = LAST_INSERT_ID();

    COMMIT;
END this_proc $$

-- ---------------------------------------------------------------------
-- sp_update_booking_status
--
-- Changes a booking's status. The AFTER UPDATE trigger writes the
-- transition to booking_status_history using @rentease_actor_id, which
-- this procedure sets before issuing the UPDATE.
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_update_booking_status $$

CREATE PROCEDURE sp_update_booking_status (
    IN p_booking_id BIGINT UNSIGNED,
    IN p_new_status ENUM('pending', 'confirmed', 'active', 'completed', 'cancelled'),
    IN p_actor_id   BIGINT UNSIGNED
)
this_proc: BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SET @rentease_actor_id = p_actor_id;

    UPDATE bookings
    SET status = p_new_status
    WHERE id = p_booking_id;

    IF ROW_COUNT() = 0 THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Booking not found';
    END IF;

    COMMIT;
END this_proc $$

-- ---------------------------------------------------------------------
-- sp_check_item_availability
--
-- Read-only helper: returns 1 row with is_available (0/1) for an item
-- over a date range. Used by the browsing/search flow (Section 4.1),
-- separate from sp_create_booking's locking check (which is the one
-- that actually guarantees safety at write time).
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_check_item_availability $$

CREATE PROCEDURE sp_check_item_availability (
    IN p_item_id        BIGINT UNSIGNED,
    IN p_start_datetime  DATETIME,
    IN p_end_datetime    DATETIME
)
BEGIN
    SELECT
        CASE WHEN COUNT(*) = 0 THEN 1 ELSE 0 END AS is_available
    FROM bookings
    WHERE item_id = p_item_id
      AND status IN ('pending', 'confirmed', 'active')
      AND start_datetime < p_end_datetime
      AND end_datetime   > p_start_datetime;
END $$

DELIMITER ;
