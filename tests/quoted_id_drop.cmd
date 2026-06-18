-- Test: DROP with a backtick-quoted reserved-name column.
-- DROP is a deferred command; NAMES after RUN should list ID and USE (not AS).
USE "tests/data/reserved_cols.csv"
DROP `AS`
RUN
NAMES
QUIT
