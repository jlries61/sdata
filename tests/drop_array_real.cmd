-- 2026-08-13 re-audit PC-4: DROP on a real (DIM'd, permanent) array's base
-- name must delete all of its element columns, and (per design.md sec3.4's
-- "arrays" framing, symmetric with the virtual-array case) the array's own
-- registration too -- otherwise the name stays blocked from later reuse
-- (ADR-0012 / PC-2) even though its data is gone. Re-DIMming F afterward
-- proves the name was fully freed, not left as a zombie registration.
REPEAT 1
DIM F(1 TO 3)
LET F(1) = 10
LET F(2) = 20
LET F(3) = 30
LET C = 99
DROP F
RUN
NAMES
REPEAT 1
DIM F(1 TO 2)
LET F(1) = 100
LET F(2) = 200
RUN
NAMES
QUIT
