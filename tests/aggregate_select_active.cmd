-- AGGREGATE: respects the active SELECT filter, then clears it.  The second
-- AGGREGATE (no SELECT) sees all rows, proving the filter was cleared.
USE "tests/data/sample.csv"
SELECT VAL1 > 5
BY CATEGORY$
AGGREGATE NPOS=N() TOT=SUM(VAL1)
DISPLAY
USE "tests/data/sample.csv"
BY CATEGORY$
AGGREGATE NALL=N()
DISPLAY
QUIT
