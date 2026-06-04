-- Positional merge: left input (merge_short) has 1 row, right (merge_b) has 2.
-- Row 2 of merge_short is padded with missing for X; ID comes from merge_b.
USE "tests/data/merge_short.csv", "tests/data/merge_b.csv"
PRINT ID X Y
RUN
NEW
END
