-- STATS: lowercase stat names are accepted; column headers are upper-cased.
USE "tests/data/sample.csv"
STATS VAL1 /STATS=n mean std
QUIT
