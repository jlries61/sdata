-- PD-6/ADR-0019 regression (positive case): a column whose FIRST value is
-- numeric but whose LATER values (still within the default NSCAN=20 scan
-- window) are non-numeric must be retyped character -- not locked in as
-- numeric by the old first-value-wins behavior. The bad values start at
-- row 11, not row 1, so this cannot be explained by the old logic
-- coincidentally producing the same result.
USE "tests/data/scan_window_retype.csv"
RUN
DISPLAY
QUIT
