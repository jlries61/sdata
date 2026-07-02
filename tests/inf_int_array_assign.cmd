-- Assigning Inf to an integer array element should raise domain error
REPEAT 1
DIM N%(5)
  LET X = MAXNUM() * 2.0
  LET N%(1) = X
  PRINT N%(1)
RUN
QUIT
