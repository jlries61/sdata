-- A mid-line comma before ELSE is not accepted either (the IF THEN-branch is a LET,
-- whose grammar has no comma role).
IF 1 = 1 THEN LET X = 1 , ELSE LET X = 2
QUIT
