-- Test LAG and NEXT functions with offsets and BY groups
REPEAT 10
LET GRP = IF(RECNO <= 5, 1, 2)
LET X = IF(RECNO <= 5, RECNO, RECNO - 5)
RUN
BY GRP
PRINT "GRP:" GRP "X:" X "LAG(X):" LAG("X") "LAG(X,2):" LAG("X",2) "NEXT(X):" NEXT("X") "NEXT(X,2):" NEXT("X",2)
RUN
QUIT
