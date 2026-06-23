-- AGGREGATE error #10: a deferred statement is pending (un-run).
USE "tests/data/sample.csv"
BY CATEGORY$
LET HOT = VAL1 > 5
AGGREGATE NREC=N()
QUIT
