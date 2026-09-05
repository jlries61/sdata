-- NOTE (ADR-063): a single temporary element of a mixed-class virtual
-- array (A is a permanent LET column, B is a genuine temporary SET
-- variable, per virtual_array_mixed_class_write.cmd's own setup) must
-- succeed -- Array_Element_Is_Temporary resolves V(2)'s own constituent
-- (B), not the array-level flag, which is always False for virtual arrays.
-- LET/SET are Deferred, so RUN must fire before NOTE (Immediate) can see
-- them, per note_basic.cmd's own pattern.
LET A = 1
SET B = 2
ARRAY V A B
RUN
NOTE V(2)
QUIT
