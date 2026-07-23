-- Issue #55: an empty character value is the missing value; it propagates
-- through string operations, and MISSING/N/NMISS treat it as missing.
NEW
REPEAT 2
LET S$ = ""
LET T$ = S$ + "x"
LET L = LEN(S$)
LET M% = MISSING(S$)
PRINT S$ T$ L M%
RUN
QUIT
