-- Regression test for P13 (design-vs-implementation audit,
-- .ssd/audits/2026-08-03-design-vs-implementation/report.md): a dash range
-- (VAR1-VAR2, "table order") in KEEP/DROP silently no-op'd when its
-- endpoints were still Deferred (LET-created, not yet materialized as
-- columns) at KEEP/DROP's own Declarative-tier dispatch time. Dash-range
-- resolution must be deferred to the end of the data step, like single
-- names and colon ranges already are.
LET VAR1 = 1
LET VAR2 = 2
LET VAR3 = 3
LET OTHER = 4
KEEP VAR1-VAR2
RUN
DISPLAY
NEW
LET VAR1 = 1
LET VAR2 = 2
LET VAR3 = 3
LET OTHER = 4
DROP VAR2-VAR1
RUN
DISPLAY
QUIT
