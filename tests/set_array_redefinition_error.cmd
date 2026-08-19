-- 2026-08-13 re-audit PC-2 / ADR-0012: SET may not redefine an existing
-- array as a scalar, same as LET -- design.md sec3.5: "Existing arrays may
-- not be redefined as scalar variables unless first deleted."
DIM Q(1 TO 2) /TEMP
SET Q(1) = 5
SET Q(2) = 6
RUN
SET Q = 99
RUN
QUIT
