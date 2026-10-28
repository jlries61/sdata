-- F17 regression: crosstype must be an error, not a silent no-op.
USE "tests/data/colon_ranges.csv"
RENAME X1 = X1$
QUIT
