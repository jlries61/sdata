-- A comma that ENDS the THEN-branch line still lets ELSE reach across it, and PRINT keeps
-- its own optional comma, so both of these are fine.
IF 1 = 1 THEN LET X = 1,
ELSE LET X = 2
PRINT X
IF 1 = 2 THEN PRINT 1, ELSE PRINT 2
RUN
QUIT
