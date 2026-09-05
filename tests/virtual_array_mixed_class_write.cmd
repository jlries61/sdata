-- ADR-0023 (sdata-core issue #118): a virtual array can alias constituents
-- of different storage classes (A is a permanent LET column, B is a
-- genuine temporary SET variable). Element writes must dispatch by each
-- element's own resolved constituent, not by the array-level flag (always
-- False for virtual arrays) -- so SET can reach the temporary element and
-- LET can reach the permanent one, through array syntax, exactly as bare
-- assignment to A/B already allows.
REPEAT 1
LET A = 1
SET B = 2
ARRAY V A B
SET V(2) = 30
LET V(1) = 10
PRINT A B
RUN

QUIT
