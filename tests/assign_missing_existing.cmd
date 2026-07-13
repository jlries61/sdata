-- Issue #51: assigning a missing value to an EXISTING column must succeed
-- (recoding a sentinel to missing in place), matching the new-column
-- behavior.  Both numeric families and both the bare '.' literal and an
-- IF() missing result are exercised.  A variable created by an earlier LET
-- in the same block counts as "existing".
DIGITS 3
NEW
REPEAT 3
LET AGE% = 900 + RECNO()
LET AGE% = IF(AGE% = 902, ., AGE%)
LET X = RECNO() + 0.5
LET X = .
PRINT AGE% X
RUN
QUIT
