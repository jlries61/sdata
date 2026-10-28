-- F17 (2026-10-19 stress test) regression: RENAME of a DROPped name is legal
-- and replaces that column; the other cases are errors (see the sibling
-- rename_*_rejected tests).
USE "tests/data/colon_ranges.csv"
DROP Y
RENAME X1 = Y
RUN
NAMES
DISPLAY Y
END
