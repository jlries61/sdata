-- Test --ignore-math-errors flag: domain errors return MISSING (.)
-- with a warning instead of halting execution.
-- All LET assignments should succeed with MISSING results.
DIGITS 5
REPEAT 1
  LET A = LOG(0)
  LET B = SQRT(-4)
  LET C = ARCSIN(2)
  LET D = ARCCOS(-2)
  LET E = MOD(7, 0)
  PRINT "LOG(0):"     A
  PRINT "SQRT(-4):"   B
  PRINT "ARCSIN(2):"  C
  PRINT "ARCCOS(-2):" D
  PRINT "MOD(7,0):"   E
RUN
QUIT
