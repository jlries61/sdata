-- issue #67 regression: BY inside a REPEAT body, naming a variable a LET
-- in the SAME body will create, must now error rather than silently
-- succeed -- even though the LET appears textually BEFORE the BY.
-- REPEAT unconditionally clears the table (SData_Core.Table.Clear) before
-- its body starts, and LET is a deferred statement that only runs once
-- per record during RUN -- BY is declarative and dispatches immediately
-- as the body is parsed, before any deferred LET has run. So Column_Count
-- is always 0 at BY's own execution time inside a from-scratch REPEAT
-- body, regardless of textual order: there is no configuration in which
-- the old Column_Count > 0 bypass protected a real forward (or backward)
-- reference, only a footgun (see ADR-052).
NEW
REPEAT 6
LET G = (RECNO() > 3)
BY G
PRINT G
RUN
QUIT
