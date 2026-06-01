-- Error test: /INTERLEAVE without /BY= in USE.
-- Verifies the parser emits: /INTERLEAVE and /JOIN require /BY= in USE.
USE "tests/data/merge_a.csv", "tests/data/merge_b.csv" /INTERLEAVE
QUIT
