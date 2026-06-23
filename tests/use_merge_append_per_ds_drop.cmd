-- APPEND with per-dataset DROP=.
-- merge_a's X is dropped before the stack; union schema: ID, Y.
-- Rows 1-2 come from A (Y missing); rows 3-4 from B (Y set). Confirms the
-- dropped column is absent from the union and rows still stack.
USE "tests/data/merge_a.csv" (DROP=X), "tests/data/merge_b.csv" /APPEND
PRINT ID Y
RUN
NEW
END
