-- PD-7/ADR-0020 regression (boundary case): exactly 10 non-numeric-value
-- coercion warnings must all print, with NO suppression summary line. The
-- 20 rows before the bad values establish column A as numeric (inside the
-- default NSCAN=20 scan window, all-numeric); rows 21-30 (10 rows, outside
-- the window) each trip the per-value coercion warning.
USE "tests/data/coercion_cap_10.csv"
RUN
QUIT
