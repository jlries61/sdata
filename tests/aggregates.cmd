-- Test for row-wise aggregate functions
NEW
REPEAT 1
LET A = 10
LET B = 20
LET C = 60
LET D = . -- Missing

PRINT "--- Row-wise aggregates on scalars ---"
PRINT "SUM(A,B,C):" SUM(A,B,C)
PRINT "MEAN(A,B,C):" MEAN(A,B,C)
PRINT "N(A,B,C,D):" N(A,B,C,D)
PRINT "NMISS(A,B,C,D):" NMISS(A,B,C,D)
PRINT "STD(10,20,60):" STD(10,20,60)
RUN

NEW
REPEAT 1
DIM V(4)
LET V(1) = 10
LET V(2) = 20
LET V(3) = 30
LET V(4) = 40
PRINT "--- Row-wise aggregates on an array ---"
PRINT "SUM(V):" SUM(V)
PRINT "MEAN(V):" MEAN(V)
PRINT "STD(V):" STD(V)
RUN

QUIT
