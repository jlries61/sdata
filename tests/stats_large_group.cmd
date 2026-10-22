-- F50 (2026-10-19 stress test) regression: STATS and AGGREGATE over a group
-- of >= ~350,000 rows used to die with a stack overflow (the group's values
-- were held on the 8 MB stack).  360000 rows: expect N=360000, MEAN=4.5.
SYSTEM "awk -f tests/data/gen_large_group.awk > tests/data/stats_large_group_gen.csv"
USE "tests/data/stats_large_group_gen.csv"
STATS X /STATS=N MEAN
USE "tests/data/stats_large_group_gen.csv"
AGGREGATE N = N(X) M = MEAN(X) P = PCTL(X,90)
DISPLAY
SYSTEM "rm -f tests/data/stats_large_group_gen.csv"
END
