-- PC-3 (2026-08-13 re-audit): DIM must be allowed to replace an existing
-- virtual array with a real array, per design.md sec3.5 ("Virtual array may
-- be replaced by permanent/temporary array using DIM (no effect on former
-- constituent variables)"). Audit's own repro. A and B must remain
-- independently referenceable, with their original values, after the
-- replacement.
LET A = 1
LET B = 2
ARRAY V A B
RUN
DIM V(1 TO 2) /TEMP
PRINT A B
RUN
QUIT
