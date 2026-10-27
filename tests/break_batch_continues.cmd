-- F12 (2026-10-19 stress test) regression: in non-interactive mode BREAK
-- traces to stderr and continues with the REST of the record (design.md
-- section 7.1); statements after a triggered BREAK must still run.
REPEAT 2
LET I = RECNO()
BREAK WHEN I = 1
PRINT "after break", I
RUN
QUIT
