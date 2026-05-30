-- Error test: two SAVE targets with the same filename.
-- Verifies the executor emits: duplicate SAVE file: tests/data/out_dup.csv.
USE "tests/data/merge_a.csv"
SAVE "tests/data/out_dup.csv", "tests/data/out_dup.csv"
RUN
QUIT
