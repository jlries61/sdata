-- Issue #65: ^ and ** must both work as exponentiation, in every
-- expression-parsing entry point (LET/assignment and SELECT filter alike).
NEW
REPEAT 4
LET X = RECNO
LET Y = X ^ 2
LET Z = X ** 2
RUN
PRINT X Y Z
RUN

-- SELECT filter (goes through the shared evaluator's own parser) accepts
-- both spellings too.
NEW
REPEAT 4
LET X = RECNO
RUN
SELECT X ^ 2 > 4
RUN
PRINT "SEL-CARET:" X
RUN

NEW
REPEAT 4
LET X = RECNO
RUN
SELECT X ** 2 > 4
RUN
PRINT "SEL-STARSTAR:" X
RUN

QUIT
