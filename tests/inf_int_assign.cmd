-- Assigning Inf to integer variable should raise domain error
DIGITS 5
REPEAT 1
  LET X = MAXNUM() * 2.0
  LET N% = X
  PRINT N%
RUN
QUIT
