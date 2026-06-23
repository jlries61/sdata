-- AGGREGATE error #9: duplicate outvar name within one command.
USE "tests/data/sample.csv"
AGGREGATE A=SUM(VAL1) A=N()
QUIT
