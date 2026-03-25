-- Test: numeric column whose first data value is missing (.) should be
-- detected as numeric, not string.  Regression test for type-scan fix.
USE "tests/data/missing_first.csv"
PRINT X, Y
RUN
QUIT
