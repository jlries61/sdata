-- Test LAG/NEXT with offset n and BY-group boundaries inside a filtered view.
--
-- Setup: 10 records, X=1..10, GRP=1 for X<=5, GRP=2 for X>5.
-- BY GRP sorts the table; SELECT keeps only odd-X rows.
--
-- After BY GRP sort the physical order is:
--   phys1(X=1,GRP=1) phys2(X=3,GRP=1) phys3(X=5,GRP=1)
--   phys4(X=7,GRP=2) phys5(X=9,GRP=2)
--   phys6(X=2,GRP=1) phys7(X=4,GRP=1)
--   phys8(X=6,GRP=2) phys9(X=8,GRP=2) phys10(X=10,GRP=2)
--
-- SELECT MOD(X,2)=1 admits phys1-5 as logical rows 1-5.
-- BY-group boundary: logical 3 (X=5, GRP=1) -> logical 4 (X=7, GRP=2).
--
-- Expected LAG/NEXT behaviour (. = missing):
--   Logical  X  LAG1  LAG2  NEXT1  NEXT2
--      1     1    .     .    3      5       (no prev; NEXT crosses no boundary)
--      2     3    1     .    5      .       (LAG2 too far back; NEXT2 crosses group)
--      3     5    3     1    .      .       (NEXT1 crosses group boundary)
--      4     7    .     .    9      .       (LAG1 crosses group; NEXT2 out of bounds)
--      5     9    7     .    .      .       (LAG2 crosses group; no next)
REPEAT 10
LET X = RECNO
LET GRP = IF(X <= 5, 1, 2)
RUN

BY GRP
SELECT MOD(X, 2) = 1
PRINT "X:" X "LAG1:" LAG("X") "LAG2:" LAG("X",2) "NEXT1:" NEXT("X") "NEXT2:" NEXT("X",2)
RUN

QUIT
