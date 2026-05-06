-- Test NaN detection from Inf arithmetic (Inf - Inf = NaN = error)
DIGITS 5
REPEAT 1
  LET X = MAXNUM() * 2.0
  LET Y = -(MAXNUM() * 2.0)
  LET Z = X + Y
  PRINT Z
RUN
QUIT
