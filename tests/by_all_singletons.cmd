-- Edge case: every record has a distinct BY key -> N singleton groups.
-- Every record must show BOG=1 and EOG=1.
REPEAT 4
LET KEY = RECNO()
LET VAL = RECNO()
RUN

BY KEY
PRINT VAL BOG() EOG()
RUN
QUIT
