-- 2026-08-13 re-audit PC-2 / ADR-0012: LET may not redefine an existing
-- array as a scalar -- design.md sec3.5: "Existing arrays may not be
-- redefined as scalar variables unless first deleted."
DIM Q(1 TO 3)
LET Q(1) = 5
LET Q(2) = 6
LET Q(3) = 7
RUN
LET Q = 99
RUN
QUIT
