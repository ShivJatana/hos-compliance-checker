-- =====================================================================
-- HOURS-OF-SERVICE COMPLIANCE CHECKS (Canada, south of 60°N)
-- Rules checked, from the Commercial Vehicle Drivers Hours of Service
-- Regulations (SOR/2005-313), "day" limits and Cycle 1:
--   R1  No more than 13 hours of driving in a day
--   R2  No more than 14 hours of on-duty time (driving + on duty) in a day
--   R3  Cycle 1: no more than 70 hours on duty in any 7 consecutive days
-- The daily 10-hour off-duty rule is the mirror image of R2 on a
-- midnight-to-midnight log (off duty = 24 - on duty), so it is not listed
-- separately: every R2 violation is also an off-duty shortfall.
-- Simplification: a "day" is the calendar day (midnight to midnight).
-- The 16-hour elapsed work-shift rule and deferral options are not checked.
-- Requires SQLite 3.25+ (window functions); DB Browser for SQLite 3.12+ has it.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1.1  Daily totals per driver (the base for every check)
-- ---------------------------------------------------------------------
DROP VIEW IF EXISTS daily_totals;
CREATE VIEW daily_totals AS
SELECT driver_id,
       log_date,
       ROUND(SUM(CASE WHEN duty_status = 'D' THEN hours ELSE 0 END), 2)          AS driving_hrs,
       ROUND(SUM(CASE WHEN duty_status IN ('D', 'ON') THEN hours ELSE 0 END), 2) AS on_duty_hrs,
       ROUND(SUM(CASE WHEN duty_status IN ('OFF', 'SB') THEN hours ELSE 0 END), 2) AS off_duty_hrs
FROM duty_status_log
GROUP BY driver_id, log_date;

SELECT * FROM daily_totals ORDER BY driver_id, log_date LIMIT 20;


-- ---------------------------------------------------------------------
-- 1.2  Every violation, one row per driver-day-rule
-- ---------------------------------------------------------------------
DROP VIEW IF EXISTS violations;
CREATE VIEW violations AS
WITH cycle AS (
    SELECT driver_id, log_date, on_duty_hrs,
           SUM(on_duty_hrs) OVER (PARTITION BY driver_id ORDER BY log_date
                                  ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS on_duty_7day,
           COUNT(*)         OVER (PARTITION BY driver_id ORDER BY log_date
                                  ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS days_in_window
    FROM daily_totals
)
SELECT driver_id, log_date, 'R1 Driving > 13 h' AS rule, driving_hrs AS value
FROM daily_totals WHERE driving_hrs > 13
UNION ALL
SELECT driver_id, log_date, 'R2 On duty > 14 h', on_duty_hrs
FROM daily_totals WHERE on_duty_hrs > 14
UNION ALL
SELECT driver_id, log_date, 'R3 Cycle 1 > 70 h / 7 days', ROUND(on_duty_7day, 2)
FROM cycle WHERE days_in_window = 7 AND on_duty_7day > 70;

SELECT * FROM violations ORDER BY log_date, driver_id;


-- ---------------------------------------------------------------------
-- 2.1  Fleet summary: driver-days worked and violations by rule
-- ---------------------------------------------------------------------
SELECT (SELECT COUNT(*) FROM daily_totals WHERE on_duty_hrs > 0) AS driver_days_worked,
       rule,
       COUNT(*) AS violations,
       COUNT(DISTINCT driver_id) AS drivers_involved
FROM violations
GROUP BY rule
ORDER BY rule;


-- ---------------------------------------------------------------------
-- 2.2  Compliance rate: % of worked driver-days with no daily violation
-- ---------------------------------------------------------------------
SELECT COUNT(*) AS driver_days_worked,
       SUM(NOT EXISTS (SELECT 1 FROM violations v
                        WHERE v.driver_id = d.driver_id AND v.log_date = d.log_date
                          AND v.rule NOT LIKE 'R3%')) AS compliant_days,
       ROUND(100.0 * SUM(NOT EXISTS (SELECT 1 FROM violations v
                        WHERE v.driver_id = d.driver_id AND v.log_date = d.log_date
                          AND v.rule NOT LIKE 'R3%')) / COUNT(*), 1) AS daily_compliance_pct
FROM daily_totals d
WHERE d.on_duty_hrs > 0;


-- ---------------------------------------------------------------------
-- 2.3  Violations by driver (who needs coaching?)
-- ---------------------------------------------------------------------
SELECT d.driver_id, d.driver_type,
       COUNT(v.rule) AS total_violations,
       SUM(v.rule LIKE 'R1%') AS r1_driving,
       SUM(v.rule LIKE 'R2%') AS r2_on_duty,
       SUM(v.rule LIKE 'R3%') AS r3_cycle
FROM drivers d
LEFT JOIN violations v ON v.driver_id = d.driver_id
GROUP BY d.driver_id
ORDER BY total_violations DESC, d.driver_id;


-- ---------------------------------------------------------------------
-- 2.4  Violations by driver type
-- ---------------------------------------------------------------------
SELECT d.driver_type,
       COUNT(DISTINCT d.driver_id) AS drivers,
       COUNT(v.rule) AS violations,
       ROUND(1.0 * COUNT(v.rule) / COUNT(DISTINCT d.driver_id), 1) AS violations_per_driver
FROM drivers d
LEFT JOIN violations v ON v.driver_id = d.driver_id
GROUP BY d.driver_type
ORDER BY violations_per_driver DESC;


-- ---------------------------------------------------------------------
-- 3.1  Days off: do the drivers with cycle violations rest less?
-- ---------------------------------------------------------------------
SELECT t.driver_id,
       SUM(t.on_duty_hrs = 0) AS days_off_in_28,
       ROUND(AVG(CASE WHEN t.on_duty_hrs > 0 THEN t.driving_hrs END), 1) AS avg_driving_per_work_day,
       (SELECT COUNT(*) FROM violations v WHERE v.driver_id = t.driver_id AND v.rule LIKE 'R3%') AS cycle_violations
FROM daily_totals t
GROUP BY t.driver_id
ORDER BY cycle_violations DESC, days_off_in_28
LIMIT 8;
