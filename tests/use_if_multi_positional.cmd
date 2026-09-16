-- Multi-dataset positional USE, IF= on both specs (ADR-074/sdata#92).
-- use_if_a filtered to YEARA=2026 (rows 2,3); use_if_b filtered to
-- YEARB=2025 (rows 1,2) -- both filters evaluate against ORIGINAL
-- column names, independently, before the positional combine.
USE "tests/data/use_if_a.csv" (IF=YEARA=2026), "tests/data/use_if_b.csv" (IF=YEARB=2025)
PRINT IDA XA IDB YB
RUN
NEW
END
