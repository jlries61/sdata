-- Test: RENAME with a backtick-quoted reserved-name column.
-- `AS` is a reserved keyword; quoting allows it to be renamed to ASCOL.
-- NAMES should list ID ASCOL USE (bare names, no backticks).
USE "tests/data/reserved_cols.csv"
RENAME `AS`=ASCOL
NAMES
RUN
QUIT
