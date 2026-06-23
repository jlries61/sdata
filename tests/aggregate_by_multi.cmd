-- AGGREGATE: multiple BY variables.
USE "tests/data/agg_multi.csv"
BY REGION$ DEPT$
AGGREGATE TOTAL=SUM(AMOUNT) NREC=N()
DISPLAY
QUIT
