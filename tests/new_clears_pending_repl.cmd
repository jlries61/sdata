-- REPL parity companion to new_clears_pending.cmd: batch's Stmt_NEW fix
-- should now match REPL's already-correct Clear_Active_Program behavior.
USE MOCK
SET LEFTOVER = 1
NEW
PRINT LEFTOVER
RUN
QUIT
