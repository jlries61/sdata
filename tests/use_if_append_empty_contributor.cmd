-- /APPEND where one spec's IF= drops every row of that input
-- (ADR-074/sdata#92 -- systems-designer 02-systems-designer.md Sec7).
-- use_if_a.csv: no row has YEARA=1999, so this spec contributes 0 rows.
-- Confirms the empty snapshot still participates correctly in /APPEND's
-- column-union logic (schema still includes IDA/XA/YEARA) and that
-- Combine_Append treats it identically to a naturally-empty input.
USE "tests/data/use_if_a.csv" (IF=YEARA=1999), "tests/data/use_if_b.csv" /APPEND
PRINT IDA XA IDB YB YEARB
RUN
NEW
END
