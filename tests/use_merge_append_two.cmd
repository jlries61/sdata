-- APPEND: vertically concatenate two datasets with disjoint columns.
-- merge_a.csv: ID,X (1,10),(2,20).  merge_b.csv: ID,Y (1,100),(2,200).
-- ID is numeric in both -> single ID column. Union schema: ID, X, Y.
-- Rows 1-2 come from A (Y missing); rows 3-4 come from B (X missing).
USE "tests/data/merge_a.csv", "tests/data/merge_b.csv" /APPEND
PRINT ID X Y
RUN
NEW
END
