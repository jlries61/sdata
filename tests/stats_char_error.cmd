-- STATS: a value statistic (MEAN) on a character variable is an error.
USE "tests/data/sample.csv"
STATS CATEGORY$ /STATS=MEAN
QUIT
