-- ADR-0023 companion: a Real_Array (DIM'd) element's storage class is
-- authoritative and uniform for the whole array by construction (DIM
-- .../TEMP applies to every element), so it must keep rejecting LET the
-- same way it did before the per-element dispatch change for virtual
-- arrays -- Real_Array wasn't affected by that change, and this regression
-- test locks that in.
REPEAT 1
DIM T(1 TO 2) /TEMP
SET T(1) = 5
LET T(1) = 6
RUN
QUIT
