-- Test WRITE command: only explicitly written records appear in output.

-- Part 1: of 5 records created, write only those with RECNO() <= 3;
-- print inside the same step to confirm which records are written.
NEW
REPEAT 5
LET N = RECNO()
IF RECNO() <= 3 THEN
  PRINT "Writing N=" N
  WRITE
END IF
RUN

-- Part 2: filter mock data to odd-ID records only using WRITE
NEW
USE "mock"
IF MOD(ID, 2) = 1 THEN
  PRINT "Writing ID=" ID "NAME=" NAME$
  WRITE
END IF
RUN

QUIT
