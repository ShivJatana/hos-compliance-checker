-- =====================================================================
-- STEP 0: CREATE THE DATABASE (run once)
-- 1. DB Browser for SQLite -> New Database -> save as hos.db
-- 2. Execute SQL tab -> paste this file -> Run -> Write Changes
-- 3. File -> Import -> Table from CSV file -> select both files in data/
--    (tick "Column names in first line"; import into the existing tables)
-- 4. Write Changes (Ctrl+S)
-- =====================================================================

CREATE TABLE drivers (
    driver_id      TEXT PRIMARY KEY,
    driver_type    TEXT,     -- Long haul, Regional, Cross-border
    home_terminal  TEXT
);

-- One row per duty-status change, like an ELD log.
-- duty_status: OFF = off duty, SB = sleeper berth, D = driving,
--              ON = on duty not driving (inspections, loading, customs)
-- Segments are split at midnight, so each row belongs to one log_date.
CREATE TABLE duty_status_log (
    log_id       TEXT PRIMARY KEY,
    driver_id    TEXT REFERENCES drivers(driver_id),
    log_date     TEXT,
    duty_status  TEXT,
    start_time   TEXT,       -- HH:MM
    end_time     TEXT,       -- HH:MM (24:00 = midnight)
    hours        REAL
);
