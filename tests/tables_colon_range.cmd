-- F36 (2026-10-19 stress test) regression: TABLES X1:X2 gives one one-way
-- table per variable in the range (it used to fail with
-- 'Unrecognized command "X2"').
USE "tests/data/colon_ranges.csv"
TABLES X1:X2
QUIT
