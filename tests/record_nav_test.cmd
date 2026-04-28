-- Test BOF, EOF, LAG, OBS functions
USE "mock"
LET PREV_ID = LAG("ID")
LET FIRST    = BOF()
LET LAST     = EOF()
PRINT "REC:" RECNO() "ID:" ID "LAG_ID:" PREV_ID "BOF:" FIRST "EOF:" LAST
RUN

-- Test OBS: load mock data, then access specific records
NEW
USE "mock"
-- We want to access the loaded table. We use a 1-record iteration by deleting others, 
-- or just printing on the first record.
IF RECNO() = 1 THEN
  LET R1_NAME$ = OBSC$("NAME$", 1)
  LET R3_ID    = OBS("ID", 3)
  PRINT "Row 1 NAME:" R1_NAME$
  PRINT "Row 3 ID:"   R3_ID
END IF
RUN
QUIT
