-- Error test: /BY= references a variable not present in the first input.
-- Verifies that the executor emits a clear error naming the missing variable.
USE "tests/data/merge_a.csv", "tests/data/merge_b.csv" /BY=NoSuchVar
QUIT
