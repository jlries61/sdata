-- Test MISSING value propagation through arithmetic, comparisons,
-- and function calls.  Also tests IF() with a MISSING condition.
DIGITS 5
REPEAT 1
  LET X = .          -- explicit MISSING literal
  LET A = X + 1      -- MISSING propagates through addition
  LET B = X * 2      -- MISSING propagates through multiplication
  LET C = X / 2      -- MISSING propagates through division
  LET D = -X         -- MISSING propagates through negation
  LET E = ABS(X)     -- MISSING propagates through unary function
  LET F = MISSING(X) -- MISSING() predicate: 1 when arg is missing
  LET G = MISSING(1) -- MISSING() predicate: 0 when arg is present
  -- IF with MISSING condition returns MISSING
  LET H = IF(X, 99, 0)
  -- IF with MISSING check branch
  LET I = IF(MISSING(X), 99, 0)
  -- NMISS counts missing values across a list
  LET J = NMISS(X, 1, X, 2)
  PRINT "X:"       X
  PRINT "X+1:"     A
  PRINT "X*2:"     B
  PRINT "X/2:"     C
  PRINT "-X:"      D
  PRINT "ABS(X):"  E
  PRINT "MSS(X):"  F
  PRINT "MSS(1):"  G
  PRINT "IF(.,..):" H
  PRINT "IF(M,99):" I
  PRINT "NMISS:"   J
RUN
QUIT
