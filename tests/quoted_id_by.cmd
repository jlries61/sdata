-- Test: BY with a backtick-quoted reserved-name column.
-- Each row of reserved_cols.csv has a distinct AS value (10 and 20),
-- so each forms a singleton group (BOG=1 EOG=1 for both).
USE "tests/data/reserved_cols.csv"
BY `AS`
PRINT `AS` BOG() EOG()
RUN
QUIT
