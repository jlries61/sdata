-- F16 (2026-10-19 stress test) regression: blank lines in a CSV are not
-- records -- they used to become phantom all-missing rows (or, mid-file, a
-- row plus a "1 of 2 expected fields" warning).  A line holding only a
-- delimiter is still a record with both fields missing: expect 4 records.
USE "tests/data/blank_lines.csv"
DISPLAY
END
