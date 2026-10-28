-- F45 (2026-10-19 stress test) regression: AND/OR do not evaluate a right
-- operand that cannot change the result, so the usual guard idiom works.
REPEAT 1
LET X = 0
IF X <> 0 AND 1/X > 1 THEN PRINT "yes" ELSE PRINT "guarded AND"
IF X = 0 OR 1/X > 1 THEN PRINT "guarded OR"
LET A = 0 AND 1/X
LET B = 1 OR 1/X
PRINT A, B
RUN
QUIT
