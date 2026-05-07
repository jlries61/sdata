-- SUM of Inf values propagates Inf; mixed Inf/-Inf produces NaN error
DIGITS 5
REPEAT 1
  LET A = MAXNUM() * 2.0
  LET B = -(MAXNUM() * 2.0)
  LET S = SUM(A)
  LET M = MEAN(A, B)
  PRINT S
  PRINT M
RUN
QUIT
