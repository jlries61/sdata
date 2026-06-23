-- AGGREGATE error #6: MIN does not accept a character column.
USE "tests/data/sample.csv"
BY VAL1
AGGREGATE LO=MIN(CATEGORY$)
QUIT
