-- 2026-08-20 re-audit PD-1 / sdata-core ADR-0013: LAG/NEXT across a BY-group
-- boundary when the table is genuinely out-of-order (not the pre-existing
-- filter_lag_next_by.cmd's case, where GRP already happens to be contiguous
-- by X, so a sort there is a no-op). GRP alternates every record, so under
-- the new "no forced sort" semantics every row is its own singleton group
-- -- LAG/NEXT must never see across a boundary into a neighboring record,
-- even though that record is physically adjacent in the (unsorted) table.
REPEAT 6
LET X = RECNO
LET GRP = IF(MOD(X, 2) = 1, 1, 2)
RUN

BY GRP
PRINT "X:" X "LAG1:" LAG("X") "NEXT1:" NEXT("X")
RUN
QUIT
