-- FLOOR/CEIL of Inf propagates Inf (correct IEEE 754); assignment to integer errors
DIGITS 5
REPEAT 1
  LET X = MAXNUM() * 2.0
  PRINT FLOOR(X)
  LET N% = FLOOR(X)
  PRINT N%
RUN
QUIT
