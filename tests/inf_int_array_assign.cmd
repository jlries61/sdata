-- Assigning Inf to an integer array element should raise domain error
DIM N%(5)
REPEAT 1
  LET X = MAXNUM() * 2.0
  LET N%(1) = X
  PRINT N%(1)
RUN
QUIT
