-- Issue #69: no test coverage exercises Run_REPL at all. This is the basic
-- sanity case -- immediate (REPEAT, RUN), deferred (LET, PRINT), and RUN
-- dispatch all correctly through the REPL's own dispatch loop, not batch's
-- Execute.
REPEAT 3
LET X = RECNO
LET Y = X * 2
RUN
PRINT X Y
RUN
QUIT
