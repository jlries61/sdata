-- Interleave merge /BY=ID /INTERLEAVE with disjoint keys.
-- merge_a_13.csv: IDs 1,3  (X column)
-- merge_b_24.csv: IDs 2,4  (Y column)
-- Result: 4 rows in BY-sorted order; each row has one non-missing side.
USE "tests/data/merge_a_13.csv", "tests/data/merge_b_24.csv" /BY=ID /INTERLEAVE
PRINT ID X Y
RUN
NEW
END
