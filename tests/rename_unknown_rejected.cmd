-- F17 regression: unknown must be an error, not a silent no-op.
USE "tests/data/colon_ranges.csv"
RENAME NOPE = Q
QUIT
