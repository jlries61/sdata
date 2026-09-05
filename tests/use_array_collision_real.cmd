-- ADR-0025 companion: the same collision, but with a real (DIM'd) array
-- instead of virtual -- confirms Undefine_Array (not just the virtual-only
-- primitive) is used, so a real array's registration is removed too.
DIM Q(1 TO 2)
LET Q(1) = 111
LET Q(2) = 222
RUN
USE "tests/data/array_collision_scalar.csv"
PRINT Q
RUN
QUIT
