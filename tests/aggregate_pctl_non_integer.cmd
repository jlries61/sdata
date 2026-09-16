-- AGGREGATE: PCTL's percentile argument must be an integer literal, not a
-- fractional value (ADR-075/sdata#93 -- integer-only scope decision, avoids
-- a fractional value in the STATS output column name).
USE "tests/data/sample.csv"
AGGREGATE Q=PCTL(VAL1, 25.5)
QUIT
