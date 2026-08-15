-- Core PB-11 regression: before the 2026-08-15 fix, UNSET was missing from
-- Is_Immediate, so the REPL queued it as deferred instead of dispatching it
-- at once -- and since Stmt_UNSET was also never in Process_One_Record's
-- whitelist, it silently never fired at all interactively, under any usage
-- pattern. NEW /PROGRAM clears the still-queued SET X=1 first so this
-- matches batch's already-correct isolated-UNSET result.
NEW
USE MOCK
SET X = 1
RUN
NEW /PROGRAM
UNSET X
PRINT X
RUN
QUIT
