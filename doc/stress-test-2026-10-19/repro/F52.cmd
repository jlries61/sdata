REPEAT 1
LET Q = TCF(1,-1)
PRINT Q
RUN
REM expect a domain error (df > 0); actual: runs forever (CPU-bound)
