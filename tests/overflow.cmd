-- Test for Integer Overflow
LET A% = 5000000000000000000
LET B% = 5000000000000000000
PRINT "Attempting overflow addition..."
LET C% = A% + B%
PRINT "Result:" C%
RUN

NEW
LET A% = 5000000000000000000
PRINT "Attempting overflow multiplication..."
LET D% = A% * 2
PRINT "Result:" D%
RUN

-- Test for Division by Zero
NEW
PRINT "Integer div by zero:"
LET E = 1 / 0
RUN

NEW
PRINT "Float div by zero:"
LET F = 1.0 / 0.0
RUN

-- Test for Math Domain Errors
NEW
PRINT "Log of zero:"
LET G = LOG(0)
RUN

NEW
PRINT "Log of negative:"
LET H = LOG10(-5)
RUN
QUIT
