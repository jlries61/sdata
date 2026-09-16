-- Regression for a real bug found and fixed during this workstream's own
-- implementation (ADR-074/sdata#92): X is a column of the FIRST spec
-- (merge_a.csv) but not the second (merge_c.csv, columns ID/Z). The
-- second spec's IF=X>0 must still be rejected as undefined -- confirms
-- Check_Undefined => True is scoped to THIS spec's own just-loaded
-- schema, not leaked from a prior spec via a stale PDV_Index entry
-- (Initialize_PDV must run before Check_Expr, not just before the scan).
USE "tests/data/merge_a.csv", "tests/data/merge_c.csv" (IF=X>0) /APPEND
PRINT ID X Z
RUN
QUIT
