-- Test CSV Inf parsing: Inf spellings are read as Val_Numeric
DIGITS 5
USE "tests/data/inf_values.csv"
PRINT X
PRINT Y
PRINT Z
PRINT INF(X)
PRINT INF(Y)
RUN
QUIT
