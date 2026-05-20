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

QUIT
