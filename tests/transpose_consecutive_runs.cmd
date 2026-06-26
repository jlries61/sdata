-- TRANSPOSE: BY auto-sorts the table, so non-adjacent rows with the same key
-- are merged into one block.
USE "tests/data/transpose_runs.csv"
BY g$
TRANSPOSE
DISPLAY
QUIT
