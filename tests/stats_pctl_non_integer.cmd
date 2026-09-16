-- STATS: PCTL(<p>)'s percentile argument must be an integer literal
-- (ADR-075/sdata#93).
USE "tests/data/sample.csv"
STATS VAL1 /STATS=PCTL(25.5)
QUIT
