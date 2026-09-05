-- ADR-0023 (sdata-core issue #118): a list assignment (V(i,j,k) = value)
-- spanning constituents of mixed storage class must likewise validate the
-- whole target set before writing any of it. SET V(1,2,3) hits the
-- permanent element V(1) first (list order); none of A/B/C may be written.
REPEAT 1
LET A = 1
SET B = 2
LET C = 3
ARRAY V A B C
SET V(1,2,3) = 99
PRINT A B C
RUN
QUIT
