-- ADR-0023 companion: the SET-side counterpart of
-- array_real_let_on_temp_rejected.cmd -- a permanent Real_Array element
-- must keep rejecting SET, unaffected by the per-element dispatch change
-- for virtual arrays.
REPEAT 1
DIM P(1 TO 2)
LET P(1) = 5
SET P(1) = 6
RUN
QUIT
