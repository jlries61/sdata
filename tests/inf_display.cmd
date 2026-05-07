-- Test Inf display and INF() function
DIGITS 5
REPEAT 1
  LET X = MAXNUM() * 2.0
  LET Y = -(MAXNUM() * 2.0)
  PRINT X
  PRINT Y
  PRINT INF(X)
  PRINT INF(Y)
  PRINT INF(1.0)
  PRINT INF(.)
  PRINT (INF(X) AND X > 0)
  PRINT (INF(Y) AND Y < 0)
RUN
QUIT
