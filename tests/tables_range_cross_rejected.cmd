-- F36 regression: a range cannot be crossed with '*' in TABLES.
USE "tests/data/colon_ranges.csv"
TABLES X1:X2*Y
QUIT
