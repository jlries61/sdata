-- Evaluator edge cases: rounding/truncation semantics and floor-based MOD.
-- Validates behaviour recently changed (INT = floor) and newly added
-- functions (FIX, IP, FP) against their documented contracts.
-- Reference: Ada RM A.5.3 (Float'Floor, Float'Truncation, Float'Rounding).

-- INT uses floor (rounds toward -infinity)
PRINT "INT(1.7):"   INT(1.7)
PRINT "INT(-1.7):"  INT(-1.7)
PRINT "INT(-0.3):"  INT(-0.3)

-- FIX/IP uses truncation (rounds toward zero)
PRINT "FIX(1.7):"   FIX(1.7)
PRINT "FIX(-1.7):"  FIX(-1.7)
PRINT "IP(-0.3):"   IP(-0.3)

-- FP is fractional part: x - FIX(x)
PRINT "FP(1.7):"    FP(1.7)
PRINT "FP(-1.7):"   FP(-1.7)

-- ROUND uses round-half-away-from-zero (Ada Float'Rounding)
PRINT "ROUND(0.5):"   ROUND(0.5)
PRINT "ROUND(1.5):"   ROUND(1.5)
PRINT "ROUND(2.5):"   ROUND(2.5)
PRINT "ROUND(-0.5):"  ROUND(-0.5)
PRINT "ROUND(-1.5):"  ROUND(-1.5)

-- MOD is floor-based: MOD(a,b) = a - FLOOR(a/b)*b
-- For negative operands this differs from C-style remainder
PRINT "MOD(10,3):"   MOD(10, 3)
PRINT "MOD(-7,3):"   MOD(-7, 3)
PRINT "MOD(7,-3):"   MOD(7, -3)

RUN
QUIT
