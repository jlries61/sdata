-- Error test: SAVE target with both KEEP and DROP in its paren block.
-- Verifies the executor emits: KEEP and DROP cannot both be specified on SAVE.
USE "tests/data/merge_a.csv"
SAVE "tests/data/out_a.csv" (KEEP=ID DROP=X), "tests/data/out_b.csv"
RUN
QUIT
