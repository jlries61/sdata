-- USE's per-dataset IF= uses Check_Undefined => True (ADR-074/sdata#92),
-- unlike SAVE's IF= (Check_Undefined => False, ADR-062) -- USE's IF= has
-- no later-statement completion window, so an undefined variable is
-- unconditionally an error, immediately.
USE "tests/data/merge_a.csv" (IF=NEVERDEFINED=1)
PRINT ID X
RUN
QUIT
