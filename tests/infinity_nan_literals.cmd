-- Issue #71: typed literal input syntax for IEEE 754 Infinity/NaN (.i, -.i,
-- .n). Constructs the values directly rather than only reaching them as an
-- arithmetic result (see inf_display.cmd for the pre-existing overflow path).
DIGITS 5
REPEAT 1
  LET PI = .i
  LET NI = -.i
  LET UPPER_I = .I
  LET N1 = .n
  LET UPPER_N = .N
  PRINT PI
  PRINT NI
  PRINT UPPER_I
  PRINT N1
  PRINT UPPER_N
  PRINT INF(PI)
  PRINT INF(NI)
  PRINT INF(N1)
  PRINT (PI > 0)
  PRINT (NI < 0)
  -- IEEE 754: NaN compares unequal to everything, including itself.
  PRINT (N1 = N1)
RUN
QUIT
