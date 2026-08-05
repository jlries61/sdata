-- Regression test for P16 (design-vs-implementation audit,
-- .ssd/audits/2026-08-03-design-vs-implementation/report.md): bare PRINT (no
-- arguments) must print all currently defined permanent variables for the
-- current record (design.md sec 6.2 / Help_PRINT), including ones just
-- LET-created in this same step, before the table is committed. It
-- previously read SData_Core.Table.Column_Count -- which only reflects the
-- already-committed table schema -- and printed nothing at all for a
-- fresh, USE-less step.
LET A = 1
LET B = 2
PRINT
RUN
NEW

-- Per-record: each REPEAT record must show its own value, not a stale one.
REPEAT 3
LET X = RECNO()
PRINT
RUN
NEW

-- SET (temporary/session variable) must NOT appear in bare PRINT.
LET A = 1
SET T = 99
PRINT
RUN
QUIT
