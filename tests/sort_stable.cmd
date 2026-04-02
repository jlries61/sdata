-- Test that SORT is stable (preserves original order for equal keys)
NEW
REPEAT 6
LET GRP = INT((RECNO() - 1) / 3) + 1
LET SEQ = RECNO()
RUN
SORT GRP
RUN
PRINT GRP SEQ
RUN
QUIT
