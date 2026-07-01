-- STATS: SELECT excludes all rows; pins zero-group behavior.
USE "tests/data/sample.csv"
SELECT VAL1 > 1000
STATS VAL1
QUIT
