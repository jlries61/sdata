NEW
REPEAT 10
LET X = RECNO()
LET G = (RECNO() > 5)
RUN

PRINT "--- Global Aggregates ---"
LET S_X = SUM(X)
LET M_X = MEAN(X)
LET ST_X = STD(X)
LET V_X = VAR(X)
LET MI_X = MIN(X)
LET MA_X = MAX(X)
LET N_X = N(X)
LET NM_X = NMISS(X)
PRINT "Global:" S_X M_X ST_X V_X MI_X MA_X N_X NM_X
RUN

PRINT "--- Grouped Aggregates ---"
BY G
LET GS_X = SUM(X)
LET GM_X = MEAN(X)
PRINT "Group" G ":" GS_X GM_X
RUN
