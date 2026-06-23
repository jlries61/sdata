-- AGGREGATE error #4: unknown input variable.
USE "tests/data/sample.csv"
AGGREGATE T=SUM(NOSUCHCOL)
QUIT
