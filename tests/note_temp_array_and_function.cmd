-- NOTE (ADR-059): a whole temporary array, a single temporary array
-- element, and a function call over temporaries only -- all must print,
-- none reference a permanent variable.
DIM V(1 TO 3) /TEMP
SET V(1) = 10
SET V(2) = 20
SET V(3) = 30
SET A = 3
SET B = 4
RUN
NOTE V
NOTE V(2)
NOTE SQRT(A*A + B*B)
QUIT
