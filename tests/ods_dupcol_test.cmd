-- PD-5/ADR-0018 regression: a duplicate column name in an .ods header must
-- warn AND correctly implement "last occurrence wins" (design.md sec4.2).
-- Also exercises the case-insensitive half of the warning check ("NAME" vs
-- "name") and the row-loading fix that stopped ODF from silently dropping
-- the last occurrence's data (found during this workstream's own
-- investigation, folded in -- see ADR-0018's amendment).
USE "tests/data/ods_dupcol.ods"
RUN
DISPLAY
QUIT
