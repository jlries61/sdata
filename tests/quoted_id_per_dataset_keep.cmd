-- Test: per-dataset KEEP= option with a backtick-quoted reserved-name column.
-- Only ID and AS are loaded; USE is excluded.
USE "tests/data/reserved_cols.csv" (KEEP=`AS` ID)
NAMES
RUN
QUIT
