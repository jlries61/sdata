-- F17 regression: existing must be an error, not a silent no-op.
USE "tests/data/colon_ranges.csv"
RENAME X1 = X2
QUIT
