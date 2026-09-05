-- NOTE (ADR-063): a bare whole-array reference on an all-temporary real
-- (DIM'd /TEMP) array must succeed, printing every element from
-- Start_Idx..End_Idx -- the per-element check must not false-reject a
-- uniformly-temporary array.
USE "tests/data/charset_ascii_clean.csv"
DIM V(1 TO 3) /TEMP
SET V(1) = 10
SET V(2) = 20
SET V(3) = 30
RUN
NOTE V
QUIT
