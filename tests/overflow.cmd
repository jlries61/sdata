-- Test for Integer Overflow
LET A% = 2000000000
LET B% = 2000000000
PRINT "Attempting overflow addition..."
LET C% = A% + B%
PRINT "Result:" C%

PRINT "Attempting overflow multiplication..."
LET D% = A% * 2
PRINT "Result:" D%

-- Test for Division by Zero
PRINT "Integer div by zero:"
LET E = 1 / 0
PRINT "Float div by zero:"
LET F = 1.0 / 0.0

-- Test for Math Domain Errors
PRINT "Log of zero:"
LET G = LOG(0)
PRINT "Log of negative:"
LET H = LOG10(-5)

RUN
QUIT
