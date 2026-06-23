-- AGGREGATE error #2: not a registered aggregate function.
USE "tests/data/sample.csv"
AGGREGATE BAD=FOO(VAL1)
QUIT
