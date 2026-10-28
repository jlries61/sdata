-- F50 (2026-10-19 stress test) regression: STATS over a group of
-- >= ~350,000 rows used to die with a stack overflow (the group's values
-- were held on the 8 MB stack).  360000 rows: expect N=360000, MEAN=4.5.
-- (The AGGREGATE path has its own test, aggregate_large_group, so that each
-- stays well inside the per-test time limit.)
SYSTEM "awk -f tests/data/gen_large_group.awk > tests/data/stats_large_group_gen.csv"
USE "tests/data/stats_large_group_gen.csv"
STATS X /STATS=N MEAN
SYSTEM "rm -f tests/data/stats_large_group_gen.csv"
END
