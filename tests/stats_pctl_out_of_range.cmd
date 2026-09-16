-- STATS: PCTL(<p>)'s percentile argument must be 0..100 (ADR-075/sdata#93).
USE "tests/data/sample.csv"
STATS VAL1 /STATS=PCTL(101)
QUIT
