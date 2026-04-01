-- Test SELECT ... END SELECT multi-line block parsing
NEW
USE MOCK
SELECT (ID)
  CASE (1): LET V$ = "One"
  CASE (2): LET V$ = "Two"
  OTHERWISE: LET V$ = "Other"
END SELECT
PRINT ID, V$
RUN

-- Test SELECT with multiple statements per CASE and no parentheses
NEW
USE MOCK
SELECT ID
  CASE 1: 
    LET V$ = "One"
    PRINT "Matched 1"
  CASE 2, 3:
    LET V$ = "Two or Three"
    PRINT "Matched 2 or 3"
  OTHERWISE: 
    LET V$ = "Other"
END SELECT
PRINT ID, V$
RUN

QUIT
