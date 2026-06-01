-- Error test: /JOIN and /INTERLEAVE both specified in the same USE.
-- Verifies the parser emits: /INTERLEAVE and /JOIN cannot both be specified in USE.
USE "tests/data/merge_a.csv", "tests/data/merge_b.csv" /JOIN /INTERLEAVE
QUIT
