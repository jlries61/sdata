-- REPL parity companion to new_program_test.cmd.
USE MOCK
SET X = 1
RUN
SET STALE = 99
NEW /PROGRAM
PRINT X
RUN
QUIT
