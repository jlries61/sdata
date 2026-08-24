-- PD-6/ADR-0019 regression (negative case): a non-numeric value at row 21
-- -- the first row OUTSIDE the default NSCAN=20 scan window -- must NOT
-- retype the column, proving the fix respects the window boundary exactly
-- (catches both a "scan the whole file" wrong implementation and a subtler
-- off-by-one). The column stays numeric; row 21's bad value gets the
-- ordinary per-value "stored as missing" coercion warning, unchanged from
-- before this fix.
USE "tests/data/scan_window_boundary.csv"
RUN
DISPLAY
QUIT
