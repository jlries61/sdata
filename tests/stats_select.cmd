-- STATS: active SELECT is respected during the scan, then cleared.
USE "tests/data/sample.csv"
SELECT VAL1 > 5
STATS VAL1
QUIT
