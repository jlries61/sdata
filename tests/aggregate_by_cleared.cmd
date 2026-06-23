-- AGGREGATE: the active BY list is cleared afterward.  A second AGGREGATE with
-- no BY therefore collapses the whole table to one row.
USE "tests/data/sample.csv"
BY CATEGORY$
AGGREGATE NREC=N()
DISPLAY
AGGREGATE GRAND=N()
DISPLAY
QUIT
