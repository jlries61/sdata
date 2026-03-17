-- Test SORT command with data that requires genuine reordering.

-- Part 1: single-variable sort (numeric, descending input -> ascending output)
NEW
REPEAT 5
LET N = 6 - RECNO()
RUN
SORT N
RUN
PRINT N
RUN

-- Part 2: multi-variable sort (primary GRP ascending, secondary VAL ascending)
-- Records created with GRP=2 first, then GRP=1, so sort must reorder them.
NEW
REPEAT 6
IF RECNO() <= 3 THEN LET GRP = 2 ELSE LET GRP = 1
LET VAL = MOD(RECNO(), 3) + 1
RUN
SORT GRP VAL
RUN
PRINT GRP VAL
RUN

QUIT
