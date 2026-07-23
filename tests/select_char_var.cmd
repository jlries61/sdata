-- Issue #73 (real fix): SELECT/condition filters can reference typed ($/%)
-- columns directly. Parse_Expression's lexer now accepts the type suffix as
-- part of the identifier instead of erroring at it -- Get_Expected_Kind and
-- Variables.Get already expected the suffixed name; only the lexer lagged.
USE "tests/data/sample.csv"
SELECT CATEGORY$ = "A"
PRINT CATEGORY$ VAL1
RUN

NEW
REPEAT 6
LET N% = RECNO
RUN
SELECT N% > 3
PRINT N%
RUN
QUIT
