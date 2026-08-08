-- =====================================================================
-- RentEase MVP — Core Schema
-- Engine: MySQL 8 / MariaDB 10.11, InnoDB, utf8mb4
-- Source of truth: rentease_erd_v3.png
-- =====================================================================

DROP DATABASE IF EXISTS rentease;
CREATE DATABASE rentease
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE rentease;

SET NAMES utf8mb4;
-- SET default_storage_engine = InnoDB;

-- ---------------------------------------------------------------------
-- categories
-- ---------------------------------------------------------------------
CREATE TABLE categories (
    id          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    name        VARCHAR(100)  NOT NULL UNIQUE,
    description TEXT          NULL,
    created_at  TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at  TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP
                              ON UPDATE CURRENT_TIMESTAMP
);

-- ---------------------------------------------------------------------
-- branches
-- ---------------------------------------------------------------------
CREATE TABLE branches (
    id          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    name        VARCHAR(150)  NOT NULL,
    address     VARCHAR(255)  NOT NULL,
    city        VARCHAR(100)  NOT NULL,
    phone       VARCHAR(30)   NULL,
    is_active   BOOLEAN       NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at  TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP
                              ON UPDATE CURRENT_TIMESTAMP
);

-- ---------------------------------------------------------------------
-- users
-- ---------------------------------------------------------------------
CREATE TABLE users (
    id            BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    full_name     VARCHAR(150)  NOT NULL,
    email         VARCHAR(255)  NOT NULL UNIQUE,
    phone         VARCHAR(30)   NULL,
    password_hash VARCHAR(255)  NOT NULL,
    role          ENUM('customer', 'staff', 'super_admin') NOT NULL DEFAULT 'customer',
    is_verified   BOOLEAN       NOT NULL DEFAULT FALSE,
    is_active     BOOLEAN       NOT NULL DEFAULT TRUE,
    failed_login_attempts SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    locked_until  DATETIME      NULL,
    created_at    TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at    TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP
                                ON UPDATE CURRENT_TIMESTAMP
);

-- CREATE INDEX idx_users_role ON users (role); --skipped

-- ---------------------------------------------------------------------
-- item_catalog  (the product; independent of physical units/branches)
-- ---------------------------------------------------------------------
CREATE TABLE item_catalog (
    id          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    category_id BIGINT UNSIGNED NOT NULL,
    created_at  TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at  TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP
                                ON UPDATE CURRENT_TIMESTAMP,

    CONSTRAINT fk_item_catalog_category
        FOREIGN KEY (category_id) REFERENCES categories (id)
        ON UPDATE CASCADE ON DELETE RESTRICT
);

-- CREATE INDEX idx_item_catalog_category ON item_catalog (category_id); --skipped

-- ---------------------------------------------------------------------
-- item_photos  (belongs to the catalog product, not a physical unit)
-- ---------------------------------------------------------------------
CREATE TABLE item_photos (
    id          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    catalog_id  BIGINT UNSIGNED NOT NULL,
    url         VARCHAR(500)    NOT NULL,
    sort_order  SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    created_at  TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_item_photos_catalog
        FOREIGN KEY (catalog_id) REFERENCES item_catalog (id)
        ON UPDATE CASCADE ON DELETE CASCADE
);

-- CREATE INDEX idx_item_photos_catalog ON item_photos (catalog_id, sort_order); --

-- ---------------------------------------------------------------------
-- items  (a physical, bookable unit at one branch)
-- ---------------------------------------------------------------------
CREATE TABLE items (
    id                BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    catalog_id        BIGINT UNSIGNED NOT NULL,
    branch_id         BIGINT UNSIGNED NOT NULL,
    name              VARCHAR(150)    NOT NULL,
    description       TEXT            NULL,
    base_price_daily  DECIMAL(10,2)   NOT NULL,
    deposit_amount    DECIMAL(10,2)   NOT NULL DEFAULT 0.00,
    status            ENUM('available', 'rented', 'maintenance', 'retired')
                                      NOT NULL DEFAULT 'available',
    created_at        TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at        TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP
                                      ON UPDATE CURRENT_TIMESTAMP,

    CONSTRAINT fk_items_catalog
        FOREIGN KEY (catalog_id) REFERENCES item_catalog (id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_items_branch
        FOREIGN KEY (branch_id) REFERENCES branches (id)
        ON UPDATE CASCADE ON DELETE RESTRICT,

    CONSTRAINT chk_items_base_price CHECK (base_price_daily >= 0),
    CONSTRAINT chk_items_deposit    CHECK (deposit_amount >= 0)
);

-- ignored indexes.
-- CREATE INDEX idx_items_catalog ON items (catalog_id);
-- CREATE INDEX idx_items_branch  ON items (branch_id);
-- CREATE INDEX idx_items_status  ON items (status);

-- ---------------------------------------------------------------------
-- bookings
-- ---------------------------------------------------------------------
CREATE TABLE bookings (
    id                  BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    booking_reference   VARCHAR(30)     NOT NULL UNIQUE,
    customer_id         BIGINT UNSIGNED NOT NULL,
    item_id             BIGINT UNSIGNED NOT NULL,
    branch_pickup_id    BIGINT UNSIGNED NOT NULL,
    branch_dropoff_id   BIGINT UNSIGNED NOT NULL,
    start_datetime      DATETIME        NOT NULL,
    end_datetime        DATETIME        NOT NULL,
    status              ENUM('pending', 'confirmed', 'active', 'completed', 'cancelled')
                                        NOT NULL DEFAULT 'pending',
    base_amount         DECIMAL(10,2)   NOT NULL,
    tax_amount          DECIMAL(10,2)   NOT NULL DEFAULT 0.00,
    deposit_amount      DECIMAL(10,2)   NOT NULL DEFAULT 0.00,
    total_amount        DECIMAL(10,2)   NOT NULL,
    created_at          TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP
                                        ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_bookings_customer
        FOREIGN KEY (customer_id) REFERENCES users (id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_bookings_item
        FOREIGN KEY (item_id) REFERENCES items (id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_bookings_branch_pickup
        FOREIGN KEY (branch_pickup_id) REFERENCES branches (id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_bookings_branch_dropoff
        FOREIGN KEY (branch_dropoff_id) REFERENCES branches (id)
        ON UPDATE CASCADE ON DELETE RESTRICT,

    CONSTRAINT chk_bookings_dates CHECK (end_datetime > start_datetime),
    CONSTRAINT chk_bookings_amounts CHECK (
        base_amount >= 0 AND tax_amount >= 0
        AND deposit_amount >= 0 AND total_amount >= 0
    )
);

-- Critical composite index for the no-double-booking availability check.
-- Query pattern: WHERE item_id = ? AND status IN (...) AND overlap(start,end)
-- ignored indexing:
-- CREATE INDEX idx_bookings_availability
--     ON bookings (item_id, start_datetime, end_datetime);

-- CREATE INDEX idx_bookings_customer ON bookings (customer_id);
-- CREATE INDEX idx_bookings_status   ON bookings (status);

-- ---------------------------------------------------------------------
-- booking_status_history
-- ---------------------------------------------------------------------
CREATE TABLE booking_status_history (
    id          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    booking_id  BIGINT UNSIGNED NOT NULL,
    old_status  ENUM('pending', 'confirmed', 'active', 'completed', 'cancelled') NULL,
    new_status  ENUM('pending', 'confirmed', 'active', 'completed', 'cancelled') NOT NULL,
    changed_by  BIGINT UNSIGNED NULL,
    changed_at  TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_bsh_booking
        FOREIGN KEY (booking_id) REFERENCES bookings (id)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_bsh_changed_by
        FOREIGN KEY (changed_by) REFERENCES users (id)
        ON UPDATE CASCADE ON DELETE SET NULL
);

-- CREATE INDEX idx_bsh_booking ON booking_status_history (booking_id, changed_at); --ignored indexing

-- ---------------------------------------------------------------------
-- payments
-- ---------------------------------------------------------------------
CREATE TABLE payments (
    id                 BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    booking_id         BIGINT UNSIGNED NOT NULL,
    type               ENUM('payment', 'refund') NOT NULL,
    amount             DECIMAL(10,2)   NOT NULL,
    method              ENUM('card', 'cash', 'bank_transfer') NOT NULL,
    gateway_reference  VARCHAR(255)    NULL,
    status             ENUM('pending', 'success', 'failed') NOT NULL DEFAULT 'pending',
    created_at         TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_payments_booking
        FOREIGN KEY (booking_id) REFERENCES bookings (id)
        ON UPDATE CASCADE ON DELETE RESTRICT,

    CONSTRAINT chk_payments_amount CHECK (amount >= 0)
);

-- ignored indexing:
-- CREATE INDEX idx_payments_booking ON payments (booking_id);
-- CREATE INDEX idx_payments_status  ON payments (status);

-- ---------------------------------------------------------------------
-- audit_logs
-- ---------------------------------------------------------------------
CREATE TABLE audit_logs (
    id          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    actor_id    BIGINT UNSIGNED NULL,
    action      VARCHAR(150)    NOT NULL,
    entity_type VARCHAR(50)     NOT NULL,
    entity_id   BIGINT UNSIGNED NOT NULL,
    created_at  TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_audit_logs_actor
        FOREIGN KEY (actor_id) REFERENCES users (id)
        ON UPDATE CASCADE ON DELETE SET NULL
);

-- ignored indexing:
-- CREATE INDEX idx_audit_logs_entity ON audit_logs (entity_type, entity_id);
-- CREATE INDEX idx_audit_logs_actor  ON audit_logs (actor_id);
