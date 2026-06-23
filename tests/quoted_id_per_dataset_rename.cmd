-- Test: per-dataset RENAME= option with a backtick-quoted reserved-name column.
-- `AS` is renamed to AS_COL at load time; NAMES shows ID AS_COL USE.
USE "tests/data/reserved_cols.csv" (RENAME=(`AS`=AS_COL))
NAMES
RUN
QUIT
