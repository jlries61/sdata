-- 2026-08-13 re-audit PC-4: KEEP on a real (DIM'd, permanent) array's base
-- name must retain all of its element columns -- the same bug PC-4 found
-- for virtual arrays applies to real arrays too, since a real array's base
-- name is likewise never itself a table column (the columns are literally
-- named F(1), F(2), F(3)).
DIM F(1 TO 3)
LET F(1) = 10
LET F(2) = 20
LET F(3) = 30
LET C = 99
KEEP F
RUN
NAMES
QUIT
