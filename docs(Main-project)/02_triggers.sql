-- =====================================================================
-- RentEase MVP — Triggers
-- =====================================================================
USE rentease;

DELIMITER $$

-- Auto-log every booking status change into booking_status_history.
-- `@rentease_actor_id` should be SET by the application (or by a calling
-- stored procedure) before the UPDATE, so we know who made the change.
-- If it's not set, changed_by is recorded as NULL.
DROP TRIGGER IF EXISTS trg_bookings_status_history $$

CREATE TRIGGER trg_bookings_status_history
    AFTER UPDATE ON bookings
    FOR EACH ROW
BEGIN
    IF OLD.status <> NEW.status THEN
        INSERT INTO booking_status_history (booking_id, old_status, new_status, changed_by, changed_at)
        VALUES (
            NEW.id,
            OLD.status,
            NEW.status,
            @rentease_actor_id,
            NOW()
        );
    END IF;
END $$

-- Also log the very first status when a booking is created.
DROP TRIGGER IF EXISTS trg_bookings_status_history_insert $$

CREATE TRIGGER trg_bookings_status_history_insert
    AFTER INSERT ON bookings
    FOR EACH ROW
BEGIN
    INSERT INTO booking_status_history (booking_id, old_status, new_status, changed_by, changed_at)
    VALUES (
        NEW.id,
        NULL,
        NEW.status,
        @rentease_actor_id,
        NOW()
    );
END $$

DELIMITER ;
