-- NOTE (ADR-063): list-form (V(1,3)) and range-form (V(1:3)) index lists
-- on an all-temporary array must succeed -- Reject_Array_Elements must
-- walk every Node in the Expression_List, including Is_Range's Expr_End,
-- the same shapes Print_Value_List itself walks.
USE "tests/data/charset_ascii_clean.csv"
DIM V(1 TO 3) /TEMP
SET V(1) = 10
SET V(2) = 20
SET V(3) = 30
RUN
NOTE V(1,3)
NOTE V(1:3)
QUIT
