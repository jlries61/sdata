-- 2026-08-19 code review round 1 (MINOR-1): permanent regression coverage
-- for the remedy the PC-2 / ADR-0012 error messages advertise -- DROP an
-- array, then redefine its freed name as a scalar. drop_array_real.cmd
-- already proves DROP frees the name for re-DIM; this proves the LET
-- (scalar) direction the SET/LET error messages specifically name.
REPEAT 1
DIM Q(1 TO 3)
LET Q(1) = 5
LET Q(2) = 6
LET Q(3) = 7
RUN
DROP Q
RUN
LET Q = 99
RUN
NAMES
QUIT
