-- Exponentiation with a negative base must compute the correct real value
-- for a whole-number exponent, not raise a runtime error.  ^ and ** resolve
-- to Ada.Numerics.Generic_Elementary_Functions."**" for Real/Real operands,
-- which is undefined for a negative base regardless of whether the exponent
-- happens to be a whole number; sdata_core-evaluator.adb's Real_Pow routes
-- whole-number exponents through the predefined "**" (Real, Integer)
-- operator instead, which has no such restriction.
--
-- Covers both operand-kind paths: L/R both Val_Integer (line ~583) and the
-- mixed/float path (line ~624), plus both ^ and ** spellings.  design.md
-- §7.3's own worked precedence example (-2^2 = 4) is included directly.
NEW
REPEAT 1
LET A = -2^2
LET B = (-2)^2
LET C = (-2)^3
LET D = (-2)^(-2)
LET E = (-1)^3
LET F = (-2)**2
LET G = 0^0
LET H = 0^2
LET I = 2^0.5
PRINT "A(-2^2):" A
PRINT "B((-2)^2):" B
PRINT "C((-2)^3):" C
PRINT "D((-2)^(-2)):" D
PRINT "E((-1)^3):" E
PRINT "F((-2)**2):" F
PRINT "G(0^0):" G
PRINT "H(0^2):" H
PRINT "I(2^0.5):" I
RUN

-- -4^0.5 remains a genuine domain error: unary minus binds tighter than ^
-- (per §7.3), so this is (-4)^0.5 -- the square root of a negative number
-- has no real result, and this must still fail rather than silently
-- succeed with a wrong value.
NEW
REPEAT 1
LET J = -4^0.5
RUN
PRINT "unreachable:" J

QUIT
