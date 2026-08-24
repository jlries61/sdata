-- PD-5/ADR-0018 regression: a duplicate column name in an .xlsx header must
-- warn AND correctly implement "last occurrence wins" (design.md sec4.2),
-- exercising the case-INSENSITIVE half of the warning check (header has
-- "NAME" and "name" -- different case, same column after $-decoration and
-- upper-casing, matching Table.Add_Column's own To_Column_Name key) and
-- the row-loading fix that stopped OOXML from silently dropping the last
-- occurrence's data (found during this workstream's own investigation,
-- folded in -- see ADR-0018's amendment).
USE "tests/data/xlsx_dupcol.xlsx"
RUN
DISPLAY
QUIT
