-- APPEND with per-dataset RENAME=().
-- merge_a's X is renamed to W before the stack; union schema: ID, W, Y.
-- Rows 1-2 come from A (W set, Y missing); rows 3-4 from B (Y set, W missing).
-- Confirms the renamed column flows through the pre-combine snapshot into the
-- APPEND union correctly.
USE "tests/data/merge_a.csv" (RENAME=(X=W)), "tests/data/merge_b.csv" /APPEND
PRINT ID W Y
RUN
NEW
END
