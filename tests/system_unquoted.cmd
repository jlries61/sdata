REM F30: an unquoted SYSTEM argument is a variable or expression.
REPEAT 1
SET C$ = "echo from variable"
RUN
SYSTEM C$
SYSTEM "echo " + "from expression"
SYSTEM "echo literal"
