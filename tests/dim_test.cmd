-- Test DIM command for real arrays

-- 1. Simple DIM
DIM X(3)
LET X(1) = 10
LET X(2) = 20
LET X(3) = 30
RUN
PRINT "X(1)=" X(1) " X(2)=" X(2) " X(3)=" X(3)

-- 2. DIM with custom bounds
DIM Y(0 TO 2)
LET Y(0) = 100
LET Y(1) = 200
LET Y(2) = 300
RUN
PRINT "Y(0)=" Y(0) " Y(1)=" Y(1) " Y(2)=" Y(2)

-- 3. Temporary DIM
DIM Z(2) /TEMP
SET Z(1) = 5
SET Z(2) = 15
PRINT "Inside RUN 3: Z(1)=" Z(1) " Z(2)=" Z(2)
RUN
-- This PRINT is part of the next implicit RUN
-- Let's add a RUN to see it.
PRINT "Outside RUN 3 (should persist): Z(1)=" Z(1)
RUN
QUIT
