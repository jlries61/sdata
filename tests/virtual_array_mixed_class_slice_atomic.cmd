-- ADR-0023 (sdata-core issue #118): a slice assignment (V(Lo:Hi) = value)
-- spanning constituents of mixed storage class must validate every index in
-- the target range before writing any of them. A and C (permanent) are
-- valid LET targets; B (temporary) is not -- the whole statement must fail
-- with none of A/B/C written, not just B left unwritten.
REPEAT 1
LET A = 1
SET B = 2
LET C = 3
ARRAY V A B C
LET V(1:3) = 99
PRINT A B C
RUN
QUIT
