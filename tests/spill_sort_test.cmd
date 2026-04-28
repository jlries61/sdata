-- Test Sorting on Spilled Table
REPEAT 10
LET X = 11 - RECNO
RUN

-- With -m 3, it should spill.
SORT X
DISPLAY X
RUN
QUIT
