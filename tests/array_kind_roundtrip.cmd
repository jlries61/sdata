-- PC-3 round-trip consistency check (systems-designer requirement): DIM
-- successfully replaces an existing virtual array with a real one; a
-- subsequent ARRAY attempt on that now-real array must be rejected. Proves
-- the replacement actually updated the array's registered kind to
-- Real_Array, not left it stale as Virtual_Array.
LET A = 1
LET B = 2
ARRAY V A B
RUN
DIM V(1 TO 2) /TEMP
LET C = 3
LET D = 4
ARRAY V C D
RUN
NAMES
QUIT
