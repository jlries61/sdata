-- Error test: KEEP and DROP both specified on the same dataset paren block.
-- Verifies the executor raises an error before attempting any merge.
USE "tests/data/merge_a.csv" (KEEP=ID DROP=X), "tests/data/merge_b.csv" /BY=ID
QUIT
