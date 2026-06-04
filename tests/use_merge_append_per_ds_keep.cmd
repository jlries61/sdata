-- APPEND with per-dataset KEEP=.
-- merge_a (KEEP=X) keeps only X; merge_b (KEEP=Y) keeps only Y.
-- Union schema: X, Y. Rows 1-2 from A (Y missing); rows 3-4 from B (X missing).
USE "tests/data/merge_a.csv" (KEEP=X), "tests/data/merge_b.csv" (KEEP=Y) /APPEND
PRINT X Y
RUN
NEW
END
