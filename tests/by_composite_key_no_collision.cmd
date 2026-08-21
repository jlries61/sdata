-- 2026-08-20 re-audit PD-1 / sdata-core ADR-0013: Partition_By_Key's
-- composite BY-key must not let two genuinely different multi-variable
-- key tuples collide into the same bucket. A naive fixed-separator string
-- join (e.g. A & "|" & B) would flatten record 1 (A="X|Y", B="Z") and
-- record 2 (A="X", B="Y|Z") to the identical string "X|Y|Z" -- these two
-- adjacent records must still form TWO separate groups, not one merged
-- group, proving the chosen key encoding is collision-free even when a
-- character BY-variable's own value contains what a naive separator would
-- have been.
REPEAT 2
LET IDX = RECNO()
LET A$ = IF(IDX = 1, "X|Y", "X")
LET B$ = IF(IDX = 1, "Z", "Y|Z")
RUN

BY A$ B$
PRINT A$ B$ BOG() EOG()
RUN
QUIT
