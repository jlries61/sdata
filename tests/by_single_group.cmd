-- Edge case: all records share the same BY key -> one group.
-- BOG=1 on first record only; EOG=1 on last record only.
REPEAT 4
LET KEY = 1
LET VAL = RECNO()
RUN

BY KEY
PRINT VAL BOG() EOG()
RUN
QUIT
