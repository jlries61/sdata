-- NOTE (ADR-063): a bare whole-array reference (no index) on a mixed-class
-- virtual array must reject the SPECIFIC permanent element it finds while
-- walking Start_Idx..End_Idx, not the array as a whole and not the wrong
-- element -- A (LET, permanent) is V(1); B (SET, temporary) is V(2), so
-- this must name "V(1)", never "V(2)" or bare "V". LET/SET are Deferred,
-- so RUN must fire before NOTE (Immediate) can see them.
LET A = 1
SET B = 2
ARRAY V A B
RUN
NOTE V
QUIT
