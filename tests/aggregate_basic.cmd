-- AGGREGATE: whole-table summary (no BY).
USE "tests/data/sample.csv"
AGGREGATE TOTAL=SUM(VAL1) MEANV=MEAN(VAL1) NREC=N()
DISPLAY
QUIT
