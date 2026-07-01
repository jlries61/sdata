-- STATS: SELECT is cleared after STATS runs.
-- After SELECT VAL1 > 5, STATS VAL1 runs on 4 filtered rows (N=4).
-- DISPLAY then shows the full 1-row stats output table without any
-- SELECT restriction, proving the filter was cleared by STATS.
USE "tests/data/sample.csv"
SELECT VAL1 > 5
STATS VAL1
DISPLAY
QUIT
