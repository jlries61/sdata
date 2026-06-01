-- Task 15 smoke test: multi-dataset positional merge through Execute_USE.
-- merge_a.csv: ID,X\n1,10\n2,20
-- merge_b.csv: ID,Y\n1,100\n2,200
-- Positional merge (no BY): rightmost column wins on collision (ID from B).
-- Result: 2 rows with columns ID, X, Y.
USE "tests/data/merge_a.csv", "tests/data/merge_b.csv"
PRINT ID X Y
RUN
END
