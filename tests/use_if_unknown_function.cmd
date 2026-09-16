-- USE's per-dataset IF= gets the same unknown-function checking as SAVE's
-- IF= (ADR-062) and STATS/AGGREGATE's other Immediate-tier expressions
-- (ADR-074/sdata#92). Checked once per spec, right after that spec's raw
-- load, before any row is filtered.
USE "tests/data/merge_a.csv" (IF=BOGUSFUNC(X)>0)
PRINT ID X
RUN
QUIT
