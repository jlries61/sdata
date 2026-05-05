-- Edge case: compound BY key (BY A B).
-- Group boundary fires when either A or B changes.
-- Four groups of 2: (1,1) (1,2) (2,1) (2,2). Each group: BOG then EOG.
REPEAT 8
LET IDX = RECNO()
LET A = IF(IDX <= 4, 1, 2)
LET B = IF(MOD(IDX, 2) = 1, 1, 2)
RUN

BY A B
PRINT A B BOG() EOG()
RUN
QUIT
