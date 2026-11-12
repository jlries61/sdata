-- NDISTINCT: number of distinct non-missing values.  Numbers compare exactly
-- (an integer and a float by value, 1 = 1.0); strings are case-sensitive;
-- missing and "" are skipped (the same "present" as N).  Works as a STATS
-- statistic (integer column), an AGGREGATE function, and row-wise in LET.
REPEAT 12
LET G = MOD(RECNO, 2)
LET X = MOD(RECNO, 4)
LET I% = MOD(RECNO, 3)
LET S$ = CHR$(65 + MOD(RECNO, 5))
IF RECNO = 7 THEN LET X = .
IF RECNO = 8 THEN LET S$ = ""
IF RECNO = 9 THEN LET X = 1.0
IF RECNO = 10 THEN LET S$ = "a"
LET T = NDISTINCT(1, 1.0, 2, .)
RUN
IF RECNO = 1 THEN PRINT "row-wise:" T
STATS X I% S$ /STATS=N NDISTINCT
RUN
REPEAT 12
LET G = MOD(RECNO, 2)
LET X = MOD(RECNO, 4)
LET S$ = CHR$(65 + MOD(RECNO, 5))
RUN
BY G
STATS X S$ /STATS=N NDISTINCT
RUN
REPEAT 12
LET G = MOD(RECNO, 2)
LET X = MOD(RECNO, 4)
RUN
BY G
AGGREGATE ND = NDISTINCT(X) NN = N(X)
DISPLAY
RUN
QUIT
