-- UNSET /ALL must not disturb a variable currently held by HOLD -- it is
-- not a genuine temporary, just a Temp_Symbols carry-over mirror.
NEW
REPEAT 3
LET VAL = RECNO()
RUN
HOLD SUMVAL
IF RECNO() = 1 THEN LET SUMVAL = 0
LET SUMVAL = SUMVAL + VAL
PRINT RECNO() SUMVAL
RUN

UNSET /ALL
PRINT SUMVAL
RUN
QUIT
