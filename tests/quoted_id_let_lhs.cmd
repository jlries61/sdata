-- Test: LET with a backtick-quoted reserved-name column on the LHS.
-- `AS` is a reserved keyword; quoting it allows assignment.
USE "tests/data/reserved_cols.csv"
LET `AS` = 5
PRINT `AS`
RUN
QUIT
