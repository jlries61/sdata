-- Test SELECT virtual table: RECNO, BOF, EOF, LAG, NEXT, BOG, EOG
-- Build a 10-record table: X=1..10, GRP=1 for X<=5, GRP=2 for X>5
REPEAT 10
LET X = RECNO
LET GRP = IF(X <= 5, 1, 2)
RUN

-- Filter to odd records only.
-- Physical rows in view: 1(X=1), 3(X=3), 5(X=5), 7(X=7), 9(X=9)
-- Logical rows:          1       2       3       4       5
-- Verifies:
--   RECNO   = logical index (1-5, not the physical 1,3,5,7,9)
--   BOF/EOF = logical boundaries
--   LAG(X)  = previous *logical* row's X (skips filtered-out even rows)
--   NEXT(X) = next *logical* row's X     (skips filtered-out even rows)
SELECT MOD(X, 2) = 1
PRINT "X:" X "RECNO:" RECNO "BOF:" BOF "EOF:" EOF "LAG:" LAG("X") "NEXT:" NEXT("X")
RUN

-- Verify BOG/EOG across BY groups within the filtered view.
-- After the previous RUN the committed table has 5 records (X=1,3,5,7,9).
-- SELECT still active; all 5 pass, so logical == physical.
-- BY GRP: GRP=1 (X=1,3,5) then GRP=2 (X=7,9)
BY GRP
PRINT "X:" X "GRP:" GRP "BOG:" BOG "EOG:" EOG
RUN

QUIT
