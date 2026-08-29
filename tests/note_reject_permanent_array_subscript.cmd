-- NOTE (ADR-059): a permanent variable used only as an array SUBSCRIPT is
-- also rejected, even though the array itself (V) is temporary --
-- Reject_If_Permanent must recurse into Expr_Array_Access's Arr_Idx list,
-- not just check the array name.
USE "tests/data/charset_ascii_clean.csv"
DIM V(1 TO 3) /TEMP
SET V(1) = 10
RUN
NOTE V(SCORE)
QUIT
