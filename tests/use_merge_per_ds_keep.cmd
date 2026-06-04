-- Multi-dataset USE with per-dataset KEEP=.
-- merge_a.csv (KEEP=X): only X survives from dataset A.
-- merge_b.csv (KEEP=Y): only Y survives from dataset B.
-- Positional merge; result has X and Y columns only (ID dropped from both).
USE "tests/data/merge_a.csv" (KEEP=X), "tests/data/merge_b.csv" (KEEP=Y)
PRINT X Y
RUN
NEW
END
