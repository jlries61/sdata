-- Test SELECT as record filter
REPEAT 10
LET X = RECNO
RUN

-- Select only odd records
SELECT MOD(X, 2) = 1
RUN
PRINT "ODD:" X
RUN

-- New selection: only records <= 5
NEW
REPEAT 10
LET X = RECNO
RUN
SELECT X <= 5
RUN
PRINT "X <= 5:" X
RUN

QUIT
