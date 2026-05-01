-- Test USE /SKIP=N: skip first 2 data rows (rows A,1 and A,4 skipped)
USE "tests/data/sample.csv" / SKIP=2
PRINT CATEGORY$ VAL1
RUN

-- Test USE /MAXROWS=N: load at most 3 rows
USE "tests/data/sample.csv" / MAXROWS=3
PRINT CATEGORY$ VAL1
RUN

-- Test SKIP and MAXROWS combined: skip 1, then load at most 2
USE "tests/data/sample.csv" / SKIP=1 / MAXROWS=2
PRINT CATEGORY$ VAL1
RUN
END
