-- Test: KEEP with a backtick-quoted reserved-name column.
-- KEEP is a deferred command; NAMES after RUN should list only `AS`.
USE "tests/data/reserved_cols.csv"
KEEP `AS`
RUN
NAMES
QUIT
