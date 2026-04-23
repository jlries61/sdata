-- Test DISPLAY command (shows Data Table records)
-- and LIST command (shows program buffer in REPL; empty buffer in batch)
REPEAT 5
LET A = RECNO
LET B = RECNO * 10
RUN

DISPLAY
DISPLAY A

SELECT A > 2
RUN
DISPLAY

QUIT
