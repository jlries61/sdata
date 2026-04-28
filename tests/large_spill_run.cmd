-- Test Large Table RUN with Spillover
REPEAT 20
LET X = RECNO
RUN

-- After commit, table should be on disk.
DISPLAY X
QUIT
