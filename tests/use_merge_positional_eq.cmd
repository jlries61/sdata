-- Positional merge with equal row counts.
-- merge_a.csv: ID,X  rows: 1,10 / 2,20
-- merge_b.csv: ID,Y  rows: 1,100 / 2,200
-- ID collides; rightmost (merge_b) wins. Result: 2 rows, columns ID X Y.
USE "tests/data/merge_a.csv", "tests/data/merge_b.csv"
PRINT ID X Y
RUN
NEW
END
