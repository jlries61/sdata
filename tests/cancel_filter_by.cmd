-- Test cancellation of SELECT filter (SELECT /ALL) and BY grouping (bare BY),
-- and that NEW resets both.

-- Build 6 records: X=1..6, GRP alternates 1/2
REPEAT 6
LET X = RECNO
LET GRP = IF(MOD(X, 2) = 1, 1, 2)
RUN

-- Activate filter and grouping
SELECT X <= 4
BY GRP
PRINT "FILTERED+GROUPED  X:" X "RECNO:" RECNO "BOG:" BOG "EOG:" EOG
RUN

-- Cancel the row filter; BY grouping should remain active
SELECT /ALL
PRINT "UNFILTERED+GROUPED  X:" X "RECNO:" RECNO "BOG:" BOG "EOG:" EOG
RUN

-- Cancel the BY grouping; filter is already gone
BY
PRINT "UNFILTERED+UNGROUPED  X:" X "RECNO:" RECNO "BOG:" BOG "EOG:" EOG
RUN

-- NEW should reset both filter and grouping for a fresh start
NEW
REPEAT 4
LET X = RECNO
RUN
SELECT X <= 2
BY X
PRINT "NEW FILTERED+GROUPED  X:" X "RECNO:" RECNO
RUN

NEW
REPEAT 3
LET X = RECNO
RUN
PRINT "AFTER NEW  X:" X "RECNO:" RECNO "BOG:" BOG "EOG:" EOG
RUN

QUIT
