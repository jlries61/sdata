-- Behavior test: WRITE with no SAVE registration falls through to the
-- legacy single-output flush and does NOT raise an error.
-- This tests the documented behavior: bare WRITE is valid with no SAVE.
USE "tests/data/merge_a.csv"
LET X = X * 2
WRITE
RUN
NEW
END
