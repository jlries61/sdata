-- STATS: bare PCTL (no percentile) in /STATS= must be a clear parse error,
-- not silently fall through to treating the last group value as the
-- percentile (ADR-075/sdata#93 -- same class of bug as
-- aggregate_pctl_missing_arg_error.cmd, on STATS's own /STATS= list).
USE "tests/data/sample.csv"
STATS VAL1 /STATS=PCTL
QUIT
