-- ADR-0023 (sdata-core issue #118): LET through array syntax must still be
-- rejected for a virtual array element whose constituent is genuinely
-- temporary -- per-element dispatch means the correct verb is still
-- enforced, just per element instead of per array. The error must name
-- what the user typed (V(2)), not the resolved constituent (B).
REPEAT 1
LET A = 1
SET B = 2
ARRAY V A B
LET V(2) = 20
RUN
QUIT
