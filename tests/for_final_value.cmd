REM FOR leaves its variable at the first out-of-range value (design.md 7.1, F13)
NEW
REPEAT 1
FOR I = 1 TO 3 : NEXT
LET A = I
FOR J = 5 TO 1 STEP -2 : NEXT
LET B = J
FOR K = 0 TO 1 STEP 0.25 : NEXT
LET C = K
FOR L = 10 TO 1 : NEXT
LET D = L
FOR M = 1 TO 3 : LET S = M : NEXT
LET E = M
PRINT A, B, C, D, E
RUN
