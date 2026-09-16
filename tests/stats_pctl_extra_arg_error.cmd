-- STATS: a parenthesized argument to any statistic OTHER than PCTL must be
-- a clear parse error (ADR-075/sdata#93 -- same class of bug as
-- aggregate_pctl_extra_arg_error.cmd, on STATS's own /STATS= list).
USE "tests/data/sample.csv"
STATS VAL1 /STATS=SUM(5)
QUIT
