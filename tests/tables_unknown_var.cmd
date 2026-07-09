-- TABLES error: a mistyped crossing variable must raise a clean error, not
-- silently produce an empty table (audit 2026-07-08 remediation #1).
-- Mirrors STATS/AGGREGATE unknown-variable validation.
USE "tests/data/sample.csv"
TABLES NOSUCHCOL
QUIT
