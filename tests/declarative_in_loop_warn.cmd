-- Regression test for P15 (design-vs-implementation audit,
-- .ssd/audits/2026-08-03-design-vs-implementation/report.md): a Declarative
-- statement (SAVE, KEEP, BY, ...) inside a FOR/WHILE/DO-UNTIL loop is not a
-- syntax error -- it still executes -- but warrants a one-time warning per
-- occurrence, not one per iteration, since it takes effect once rather than
-- being scoped to each pass through the loop.
REPEAT 1
FOR I = 1 TO 3
  LET X = I
  KEEP X
NEXT I
RUN
DISPLAY
QUIT
