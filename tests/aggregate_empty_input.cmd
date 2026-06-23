-- AGGREGATE: a SELECT that matches no rows yields an empty (0-row) output
-- table with the correct schema and no warning.
USE "tests/data/sample.csv"
SELECT VAL1 > 1000
BY CATEGORY$
AGGREGATE NREC=N() TOT=SUM(VAL1)
DISPLAY
QUIT
