-- REPL parity for UNSET /ALL: without NEW /PROGRAM first, the still-queued
-- SET A=1/SET B=2 would replay on this second RUN (REPL's Active_Program_Vec
-- persists across RUN -- see RUN's row in design.md) and silently resurrect
-- A right after UNSET /ALL removed it. NEW /PROGRAM discards the queued
-- program first, giving REPL the same result as batch.
NEW
USE MOCK
SET A = 1
SET B = 2
RUN
NEW /PROGRAM
UNSET /ALL
PRINT A
RUN
QUIT
