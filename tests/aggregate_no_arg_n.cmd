-- AGGREGATE: N() with no argument is the group row count.
USE "tests/data/sample.csv"
BY CATEGORY$
AGGREGATE NREC=N()
DISPLAY
QUIT
