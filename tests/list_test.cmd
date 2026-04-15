-- Test LIST command
REPEAT 5
LET A = RECNO
LET B = RECNO * 10
RUN

PRINT "Listing all variables:"
LIST

PRINT "Listing specific variable A:"
LIST A

SELECT A > 2
RUN
PRINT "Listing filtered (A > 2):"
LIST

QUIT
