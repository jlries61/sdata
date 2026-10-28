-- F50 regression, AGGREGATE side: a single group of 360000 rows, with a
-- percentile (which needs the whole group's values at once), used to overflow
-- the stack.  Expect N=360000, M=4.5, P=8.1.
SYSTEM "awk -f tests/data/gen_large_group.awk > tests/data/aggregate_large_group_gen.csv"
USE "tests/data/aggregate_large_group_gen.csv"
AGGREGATE N = N(X) M = MEAN(X) P = PCTL(X,90)
DISPLAY
SYSTEM "rm -f tests/data/aggregate_large_group_gen.csv"
END
