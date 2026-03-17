-- Test string functions
LET S$ = "  Hello, World!  "
PRINT "LEN:"      LEN(S$)
PRINT "TRIM$:"    TRIM$(S$)
PRINT "UCASE$:"   UCASE$(S$)
PRINT "LCASE$:"   LCASE$(S$)
PRINT "LEFT$(7):" LEFT$(TRIM$(S$), 5)
PRINT "RIGHT$(6):" RIGHT$(TRIM$(S$), 6)
PRINT "MID$(8,5):" MID$(TRIM$(S$), 8, 5)
PRINT "POS found:" POS("World", TRIM$(S$))
PRINT "POS missing:" POS("xyz", S$)
PRINT "CHR$(65):"  CHR$(65)
PRINT "STR$(42):"  STR$(42)
PRINT "VAL:"       VAL("3.14")
RUN
QUIT
