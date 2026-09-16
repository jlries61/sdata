-- /APPEND with per-dataset IF= (ADR-074/sdata#92).
-- use_if_a.csv filtered to YEARA=2026 (2 rows survive: IDA=2,3);
-- use_if_b.csv filtered to YEARB=2025 (2 rows survive: IDB=1,2).
-- Union schema: IDA, XA, YEARA, IDB, YB, YEARB (disjoint column names,
-- confirming IF= composes with /APPEND's column-union logic normally).
USE "tests/data/use_if_a.csv" (IF=YEARA=2026), "tests/data/use_if_b.csv" (IF=YEARB=2025) /APPEND
PRINT IDA XA IDB YB
RUN
NEW
END
