-- ADR-080 terminator rule: a colon separates statements on one line; this must keep working,
-- as must single-line block forms and inline IF/ELSE/ELSEIF.
LET X = 1 : PRINT X
LET Y = 0 : WHILE Y < 2 : LET Y = Y + 1 : WEND
FOR I = 1 TO 2 : PRINT I : NEXT I
IF X = 1 THEN PRINT "one" ELSE PRINT "other"
IF X = 2 THEN PRINT "two" ELSEIF X = 1 THEN PRINT "uno" ELSE PRINT "other"
RUN
QUIT
