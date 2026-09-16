-- AGGREGATE: PCTL's percentile argument must be 0..100, checked at parse
-- time (ADR-075/sdata#93).
USE "tests/data/sample.csv"
AGGREGATE Q=PCTL(VAL1, 150)
QUIT
