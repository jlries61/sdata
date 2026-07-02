REM Test 1: SET vs LET across records
REPEAT 3
SET TEMP_VAR = 100
LET PERM_VAR = 200
SET TEMP_VAR = TEMP_VAR + 1
LET PERM_VAR = PERM_VAR + 1
PRINT "Record" RECNO() ": TEMP =" TEMP_VAR ", PERM =" PERM_VAR
RUN

NEW

REM Test 2: Temporary variables should have disappeared
SET TV = 1
RUN
NEW
PRINT "TV is missing (1):" MISSING(TV)
RUN

NEW

REM Test 3: Promotion (LET promotes SET)
SET PROMOTED = 1
LET PROMOTED = PROMOTED + 9
PRINT "PROMOTED is now permanent (10):" PROMOTED
NAMES
RUN
END
