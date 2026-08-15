-- UNSET /ALL removes every genuine temporary (SET) variable, but skips a
-- name currently held by HOLD (its Temp_Symbols entry is a carry-over
-- mirror of a permanent variable, not a genuine temporary -- see Unset_All).
NEW
USE MOCK
SET A = 1
SET B = 2
RUN
UNSET /ALL
PRINT A
RUN
QUIT
