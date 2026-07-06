-- STATS parse error: /STATS may be specified at most once.
USE "tests/data/sample.csv"
STATS VAL1 /STATS=N /STATS=MEAN
QUIT
