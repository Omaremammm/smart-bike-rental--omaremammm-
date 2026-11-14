-- Smart Bike Rental App - Milestone 2
-- 04_test_constraints.sql
-- Every statement below is SUPPOSED TO FAIL. Run them one at a time in the
-- Query Tool and confirm each one shows an error. (Not part of the schema.)

-- 1. Missing/invalid foreign key: rental for a user that does not exist
INSERT INTO rentals (user_id, bike_id, start_station_id, status)
VALUES (999, 1, 1, 'active');

-- 2. Duplicate email (UNIQUE)
INSERT INTO users (email, password_hash, full_name, role)
VALUES ('omar@giu.edu', 'x', 'Duplicate Omar', 'rider');

-- 3. Invalid status (CHECK)
INSERT INTO bikes (qr_code, status, battery_level)
VALUES ('QR-9999', 'flying', 50);

-- 4. Invalid role (CHECK)
INSERT INTO users (email, password_hash, full_name, role)
VALUES ('hacker@x.com', 'x', 'Bad Role', 'superuser');

-- 5. Missing required value (NOT NULL)
INSERT INTO users (email, password_hash, role)
VALUES ('noname@giu.edu', 'x', 'rider');

-- 6. Battery out of range (CHECK)
INSERT INTO bikes (qr_code, status, battery_level)
VALUES ('QR-8888', 'available', 150);

-- 7. Second payment for the same rental (UNIQUE on rental_id)
INSERT INTO payments (rental_id, payment_method_id, amount, status)
VALUES (1, 1, 5.00, 'paid');

-- 8. Delete a user who has rentals (ON DELETE RESTRICT)
DELETE FROM users WHERE user_id = 3;
