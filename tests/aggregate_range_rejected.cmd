-- F36 regression: a variable range as an AGGREGATE argument is rejected with
-- a clear message (it used to fail with "expected ')' to close 'SUM('").
USE "tests/data/colon_ranges.csv"
AGGREGATE S = SUM(X1:X3)
QUIT
