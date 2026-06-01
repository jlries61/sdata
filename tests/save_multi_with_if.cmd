-- Follow-on C: per-record IF= filter routing.
-- big.csv receives only rows where ID>1; small.csv receives rows where ID<=1.
-- LET MARKER=1 adds a derived column to verify PDV capture.
USE "tests/data/merge_a.csv"
LET MARKER = 1
SAVE "tests/data/big.csv" (IF=ID>1), "tests/data/small.csv" (IF=ID<=1)
RUN
NEW
USE "tests/data/big.csv"
NAMES
END
