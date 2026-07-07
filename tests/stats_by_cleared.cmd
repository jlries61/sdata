-- STATS: the active BY list is cleared afterward (reshaper teardown).  The
-- second STATS, with no BY, summarizes the column N of the first stats-output
-- table across the whole table: BY cleared => one row (SUM=6); had BY persisted
-- it would split by CATEGORY$ into three rows.  Mirrors aggregate_by_cleared /
-- transpose_by_cleared so all three reshapers assert the Clear_By_Vars step.
USE "tests/data/sample.csv"
BY CATEGORY$
STATS VAL1 /STATS=N
DISPLAY
STATS N /STATS=SUM
DISPLAY
QUIT
