-- ADR-0023 (sdata-core issue #118): SET through array syntax must still be
-- rejected for a virtual array element whose constituent is genuinely
-- permanent -- the companion case to
-- virtual_array_mixed_class_let_on_temp_rejected.cmd. Before this fix, SET
-- on ANY virtual array element was rejected unconditionally regardless of
-- the element's actual class; this confirms the per-element check still
-- rejects the case it should, just for the right reason.
REPEAT 1
LET A = 1
SET B = 2
ARRAY V A B
SET V(1) = 10
RUN
QUIT
