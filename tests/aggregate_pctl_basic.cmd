-- AGGREGATE: PCTL(<invar>, <p>) whole-table summary (ADR-075/sdata#93).
-- VAL1 sorted: 1,4,7,10,13,16 (N=6, even) -- same fixture and hand-verified
-- values as stats_pctl_basic.cmd, confirming AGGREGATE and STATS agree.
USE "tests/data/sample.csv"
AGGREGATE Q1=PCTL(VAL1, 25) MED=PCTL(VAL1, 50) Q3=PCTL(VAL1, 75) MEDCHECK=MEDIAN(VAL1)
DISPLAY
QUIT
