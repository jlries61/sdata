-- 2026-08-15: NEW's own §7.1 promise ("clear... the queued program") was
-- silently broken in batch mode -- a statement queued before NEW survived
-- to the next RUN, because Stmt_NEW was never added to the Step_Start reset
-- that USE/REPEAT already get. Found while designing NEW /PROGRAM. REPL
-- already got this right via Clear_Active_Program; this locks batch in too.
USE MOCK
SET LEFTOVER = 1
NEW
PRINT LEFTOVER
RUN
QUIT
