-- Test VANDALIZE parse/validation errors

-- Error: no INTO keyword
NEW
REPEAT 3
LET X = RECNO()
RUN
VANDALIZE X OOPS Y /MISS=1.0
QUIT
