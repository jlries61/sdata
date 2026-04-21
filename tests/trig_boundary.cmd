-- Trig inverse functions at exact mathematical boundary values.
-- Uses the canonical SData function names: ARCSIN, ARCCOS.
-- Verifies: ARCSIN(1) = pi/2, ARCCOS(-1) = pi, quadrant-correct ATAN2.
DIGITS 6

-- SIN/COS at trivial points
PRINT "SIN(0):"    SIN(0)
PRINT "COS(0):"    COS(0)

-- ARCSIN/ARCCOS at exact boundary values
-- ARCSIN(1)  = pi/2 ~ 1.570796
-- ARCSIN(-1) = -pi/2 ~ -1.570796
-- ARCCOS(1)  = 0
-- ARCCOS(-1) = pi ~ 3.141593
PRINT "ARCSIN(1):"   ARCSIN(1)
PRINT "ARCSIN(-1):"  ARCSIN(-1)
PRINT "ARCCOS(1):"   ARCCOS(1)
PRINT "ARCCOS(-1):"  ARCCOS(-1)

-- ATAN2 quadrant checks
-- ATAN2(1,1)  = pi/4 ~ 0.785398
-- ATAN2(1,-1) = 3*pi/4 ~ 2.356194
-- ATAN2(-1,1) = -pi/4 ~ -0.785398
PRINT "ATAN2(1,1):"   ATAN2(1, 1)
PRINT "ATAN2(1,-1):"  ATAN2(1, -1)
PRINT "ATAN2(-1,1):"  ATAN2(-1, 1)

-- Degree-mode: SIND(90) = 1, COSD(180) = -1
PRINT "SIND(90):"   SIND(90)
PRINT "COSD(180):"  COSD(180)

RUN
QUIT
