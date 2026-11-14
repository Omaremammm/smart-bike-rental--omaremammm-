-- Smart Bike Rental App - Milestone 2
-- 01_create_tables.sql
-- Database: smart_bike_rental (PostgreSQL)
-- Tables are created in dependency order: a table that is referenced
-- by a foreign key is always created before the table that references it.

-- =====================================================================
-- 1. users  (one table for all roles: rider / admin / company)
-- =====================================================================
CREATE TABLE users (
    user_id             SERIAL PRIMARY KEY,
    email               VARCHAR(255) NOT NULL UNIQUE,
    password_hash       VARCHAR(255) NOT NULL,
    full_name           VARCHAR(100) NOT NULL,
    role                VARCHAR(20)  NOT NULL
        CHECK (role IN ('rider', 'admin', 'company')),
    user_tier           VARCHAR(20)  NOT NULL DEFAULT 'standard'
        CHECK (user_tier IN ('student', 'staff', 'standard')),
    status              VARCHAR(20)  NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'active', 'suspended')),
    tutorial_completed  BOOLEAN      NOT NULL DEFAULT FALSE,
    verification_token  VARCHAR(255),
    token_expires_at    TIMESTAMP,
    email_verified_at   TIMESTAMP,
    created_at          TIMESTAMP    NOT NULL DEFAULT NOW()
);

-- =====================================================================
-- 2. payment_methods
-- =====================================================================
CREATE TABLE payment_methods (
    payment_method_id   SERIAL PRIMARY KEY,
    -- ON DELETE CASCADE: saved cards belong to the user; if the user
    -- account is removed, their saved cards are removed with it.
    user_id             INT NOT NULL
        REFERENCES users(user_id) ON DELETE CASCADE,
    provider_token      VARCHAR(255) NOT NULL,
    card_brand          VARCHAR(30),
    last4               CHAR(4)      NOT NULL
        CHECK (last4 ~ '^[0-9]{4}$'),
    expiry_date         DATE         NOT NULL,
    is_default          BOOLEAN      NOT NULL DEFAULT FALSE
);

-- =====================================================================
-- 3. stations
-- =====================================================================
CREATE TABLE stations (
    station_id          SERIAL PRIMARY KEY,
    name                VARCHAR(100) NOT NULL,
    latitude            NUMERIC(9,6) NOT NULL
        CHECK (latitude BETWEEN -90 AND 90),
    longitude           NUMERIC(9,6) NOT NULL
        CHECK (longitude BETWEEN -180 AND 180),
    capacity            INT          NOT NULL
        CHECK (capacity > 0),
    status              VARCHAR(20)  NOT NULL DEFAULT 'active'
        CHECK (status IN ('active', 'inactive')),
    -- ON DELETE RESTRICT: a user who created stations cannot be deleted
    -- while those stations exist (keeps the audit trail).
    created_by          INT NOT NULL
        REFERENCES users(user_id) ON DELETE RESTRICT
);

-- =====================================================================
-- 4. bikes
-- =====================================================================
CREATE TABLE bikes (
    bike_id             SERIAL PRIMARY KEY,
    qr_code             VARCHAR(50)  NOT NULL UNIQUE,
    -- ON DELETE SET NULL: if a station is removed, the bike still exists
    -- but is no longer docked anywhere (NULL = not docked).
    station_id          INT
        REFERENCES stations(station_id) ON DELETE SET NULL,
    status              VARCHAR(20)  NOT NULL DEFAULT 'available'
        CHECK (status IN ('available', 'reserved', 'in_use', 'out_of_service')),
    battery_level       INT          NOT NULL
        CHECK (battery_level BETWEEN 0 AND 100),
    last_lat            NUMERIC(9,6),
    last_lng            NUMERIC(9,6),
    last_synced_at      TIMESTAMP
);

-- =====================================================================
-- 5. rentals
-- =====================================================================
CREATE TABLE rentals (
    rental_id           SERIAL PRIMARY KEY,
    -- ON DELETE RESTRICT (user, bike, start station): rental history must
    -- never disappear because someone deleted a user, bike or station.
    user_id             INT NOT NULL
        REFERENCES users(user_id) ON DELETE RESTRICT,
    bike_id             INT NOT NULL
        REFERENCES bikes(bike_id) ON DELETE RESTRICT,
    start_station_id    INT NOT NULL
        REFERENCES stations(station_id) ON DELETE RESTRICT,
    -- ON DELETE SET NULL: end station is empty until the ride ends; if the
    -- station is removed later, the rental is kept with no end station.
    end_station_id      INT
        REFERENCES stations(station_id) ON DELETE SET NULL,
    start_time          TIMESTAMP    NOT NULL DEFAULT NOW(),
    end_time            TIMESTAMP,
    status              VARCHAR(20)  NOT NULL DEFAULT 'active'
        CHECK (status IN ('active', 'paused', 'completed')),
    distance_km         NUMERIC(6,2)
        CHECK (distance_km >= 0),
    CHECK (end_time IS NULL OR end_time >= start_time)
);

-- =====================================================================
-- 6. rental_pauses
-- =====================================================================
CREATE TABLE rental_pauses (
    pause_id            SERIAL PRIMARY KEY,
    -- ON DELETE CASCADE: pauses only make sense inside their rental.
    rental_id           INT NOT NULL
        REFERENCES rentals(rental_id) ON DELETE CASCADE,
    paused_at           TIMESTAMP NOT NULL DEFAULT NOW(),
    resumed_at          TIMESTAMP,
    CHECK (resumed_at IS NULL OR resumed_at >= paused_at)
);

-- =====================================================================
-- 7. reservations
-- =====================================================================
CREATE TABLE reservations (
    reservation_id      SERIAL PRIMARY KEY,
    -- ON DELETE CASCADE: reservations are short temporary holds (15 min),
    -- so they can go away with the user or the bike.
    user_id             INT NOT NULL
        REFERENCES users(user_id) ON DELETE CASCADE,
    bike_id             INT NOT NULL
        REFERENCES bikes(bike_id) ON DELETE CASCADE,
    reserved_at         TIMESTAMP    NOT NULL DEFAULT NOW(),
    expires_at          TIMESTAMP    NOT NULL,
    status              VARCHAR(20)  NOT NULL DEFAULT 'active'
        CHECK (status IN ('active', 'expired', 'cancelled', 'converted')),
    CHECK (expires_at > reserved_at)
);

-- =====================================================================
-- 8. pricing_plans
-- =====================================================================
CREATE TABLE pricing_plans (
    pricing_plan_id     SERIAL PRIMARY KEY,
    user_tier           VARCHAR(20)  NOT NULL
        CHECK (user_tier IN ('student', 'staff', 'standard')),
    per_minute_rate     NUMERIC(6,2) NOT NULL CHECK (per_minute_rate >= 0),
    pause_rate          NUMERIC(6,2) NOT NULL CHECK (pause_rate >= 0),
    penalty_fee         NUMERIC(6,2) NOT NULL CHECK (penalty_fee >= 0),
    effective_from      TIMESTAMP    NOT NULL DEFAULT NOW(),
    -- ON DELETE RESTRICT: keep track of which admin set each price.
    created_by          INT NOT NULL
        REFERENCES users(user_id) ON DELETE RESTRICT
);

-- =====================================================================
-- 9. promo_codes
-- =====================================================================
CREATE TABLE promo_codes (
    promo_code_id       SERIAL PRIMARY KEY,
    code                VARCHAR(30)  NOT NULL UNIQUE,
    discount_percent    INT          NOT NULL
        CHECK (discount_percent BETWEEN 1 AND 100),
    valid_from          DATE         NOT NULL,
    valid_to            DATE         NOT NULL,
    max_uses            INT
        CHECK (max_uses IS NULL OR max_uses > 0),
    -- ON DELETE RESTRICT: keep track of which admin issued each code.
    created_by          INT NOT NULL
        REFERENCES users(user_id) ON DELETE RESTRICT,
    CHECK (valid_to >= valid_from)
);

-- =====================================================================
-- 10. payments
-- =====================================================================
CREATE TABLE payments (
    payment_id          SERIAL PRIMARY KEY,
    -- ON DELETE RESTRICT (rental, payment method): financial records must
    -- never be lost by deleting the rental or the card.
    -- UNIQUE on rental_id: a rental has at most one payment.
    rental_id           INT NOT NULL UNIQUE
        REFERENCES rentals(rental_id) ON DELETE RESTRICT,
    payment_method_id   INT NOT NULL
        REFERENCES payment_methods(payment_method_id) ON DELETE RESTRICT,
    -- ON DELETE SET NULL: if a promo code is removed, old payments stay.
    promo_code_id       INT
        REFERENCES promo_codes(promo_code_id) ON DELETE SET NULL,
    amount              NUMERIC(8,2) NOT NULL CHECK (amount >= 0),
    status              VARCHAR(20)  NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'paid', 'failed', 'refunded')),
    paid_at             TIMESTAMP
);

-- =====================================================================
-- 11. damage_reports
-- =====================================================================
CREATE TABLE damage_reports (
    report_id           SERIAL PRIMARY KEY,
    -- ON DELETE RESTRICT: damage history must stay with the bike and user.
    bike_id             INT NOT NULL
        REFERENCES bikes(bike_id) ON DELETE RESTRICT,
    reported_by         INT NOT NULL
        REFERENCES users(user_id) ON DELETE RESTRICT,
    description         TEXT         NOT NULL,
    status              VARCHAR(20)  NOT NULL DEFAULT 'open'
        CHECK (status IN ('open', 'in_review', 'resolved')),
    created_at          TIMESTAMP    NOT NULL DEFAULT NOW()
);

-- =====================================================================
-- 12. maintenance_tickets
-- =====================================================================
CREATE TABLE maintenance_tickets (
    ticket_id           SERIAL PRIMARY KEY,
    -- ON DELETE RESTRICT: repair history must stay with the bike (US-018).
    bike_id             INT NOT NULL
        REFERENCES bikes(bike_id) ON DELETE RESTRICT,
    -- ON DELETE SET NULL: the ticket stays even if the original report goes.
    report_id           INT
        REFERENCES damage_reports(report_id) ON DELETE SET NULL,
    opened_by           INT NOT NULL
        REFERENCES users(user_id) ON DELETE RESTRICT,
    -- ON DELETE SET NULL: closed_by is empty until the ticket is closed.
    closed_by           INT
        REFERENCES users(user_id) ON DELETE SET NULL,
    description         TEXT         NOT NULL,
    status              VARCHAR(20)  NOT NULL DEFAULT 'open'
        CHECK (status IN ('open', 'in_progress', 'closed')),
    opened_at           TIMESTAMP    NOT NULL DEFAULT NOW(),
    closed_at           TIMESTAMP,
    CHECK (closed_at IS NULL OR closed_at >= opened_at)
);

-- =====================================================================
-- 13. geofence_zones
-- =====================================================================
CREATE TABLE geofence_zones (
    zone_id             SERIAL PRIMARY KEY,
    name                VARCHAR(100) NOT NULL,
    boundary            JSONB        NOT NULL,
    is_active           BOOLEAN      NOT NULL DEFAULT TRUE,
    -- ON DELETE RESTRICT: keep track of who defined each zone.
    created_by          INT NOT NULL
        REFERENCES users(user_id) ON DELETE RESTRICT
);

-- =====================================================================
-- 14. disputes
-- =====================================================================
CREATE TABLE disputes (
    dispute_id          SERIAL PRIMARY KEY,
    -- ON DELETE RESTRICT: a disputed payment or its user cannot be deleted.
    payment_id          INT NOT NULL
        REFERENCES payments(payment_id) ON DELETE RESTRICT,
    user_id             INT NOT NULL
        REFERENCES users(user_id) ON DELETE RESTRICT,
    reason              TEXT         NOT NULL,
    status              VARCHAR(20)  NOT NULL DEFAULT 'open'
        CHECK (status IN ('open', 'approved', 'rejected')),
    -- ON DELETE SET NULL: resolved_by is empty until an admin decides.
    resolved_by         INT
        REFERENCES users(user_id) ON DELETE SET NULL,
    created_at          TIMESTAMP    NOT NULL DEFAULT NOW()
);

-- =====================================================================
-- 15. sos_events
-- =====================================================================
CREATE TABLE sos_events (
    sos_id              SERIAL PRIMARY KEY,
    -- ON DELETE RESTRICT: safety incidents must never be lost.
    rental_id           INT NOT NULL
        REFERENCES rentals(rental_id) ON DELETE RESTRICT,
    user_id             INT NOT NULL
        REFERENCES users(user_id) ON DELETE RESTRICT,
    latitude            NUMERIC(9,6) CHECK (latitude BETWEEN -90 AND 90),
    longitude           NUMERIC(9,6) CHECK (longitude BETWEEN -180 AND 180),
    triggered_at        TIMESTAMP    NOT NULL DEFAULT NOW()
);
