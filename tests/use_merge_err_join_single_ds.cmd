-- Error test: /JOIN with only a single dataset.
-- Verifies the parser emits: /INTERLEAVE and /JOIN require multiple datasets in USE.
USE "tests/data/merge_a.csv" /BY=ID /JOIN
QUIT
