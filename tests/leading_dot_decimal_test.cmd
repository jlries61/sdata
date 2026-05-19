-- Test leading-dot decimal literals (.5, .05, .1)
-- Bug: lexer emitted Token_Dot + Token_Numeric("05") for ".05"

-- Part 1: leading-dot in expression contexts
REPEAT 1
PRINT .5
PRINT .05
PRINT (.05 + .1)
IF .3 < .4 THEN PRINT "ok"
PRINT MISSING(.)
RUN

-- Part 2: leading-dot in VANDALIZE option arguments
-- /MISS=.0 means 0% miss probability, so X_V equals X exactly
NEW
REPEAT 3
LET X = RECNO()
RUN
VANDALIZE X INTO X_V /MISS=.0
RUN
PRINT X X_V
RUN

QUIT
