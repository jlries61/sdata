-- Regression: SELECT that matches zero records must produce 0-record RUN,
-- not silently run over all records.
REPEAT 3
LET X = RECNO()
RUN

BY X
SELECT X < 0
PRINT "SHOULD NOT APPEAR"
RUN
QUIT
