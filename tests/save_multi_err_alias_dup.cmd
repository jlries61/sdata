-- Error test: two SAVE targets with the same alias.
-- Verifies the executor emits: duplicate SAVE alias: A.
USE "tests/data/merge_a.csv"
SAVE "tests/data/out_a.csv" AS A, "tests/data/out_b.csv" AS A
RUN
QUIT
