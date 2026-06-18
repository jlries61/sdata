-- Test: SAVE alias name can be a backtick-quoted reserved keyword,
-- and WRITE target can reference that quoted alias.
-- Only the record with ID=1 is routed to the alias target.
USE "tests/data/reserved_cols.csv"
SAVE "tests/data/qid_alias.csv" AS `AS`
IF ID = 1 THEN WRITE `AS`
RUN
NEW
END
