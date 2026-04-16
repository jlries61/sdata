-- Test Memory-to-Disk Spillover
REPEAT 20
LET X = RECNO
RUN

-- With -m 5 (set via .flags), rows 1..15 should be on disk, 16..20 in memory.

PRINT "RECNO 1:" OBS("X", 1)
PRINT "RECNO 10:" OBS("X", 10)
PRINT "RECNO 20:" OBS("X", 20)

PRINT "Full List:"
LIST X
QUIT
