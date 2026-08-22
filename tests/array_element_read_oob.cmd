-- PC-1 (2026-08-13 re-audit): reading past a real (DIM'd) array's declared
-- bounds must raise, matching design.md sec2.5/3.3 and Set_Array_Element's
-- existing out-of-bounds behavior (LET F(5)=... already errors the same way).
DIM F(1 TO 3)
LET F(1) = 10
PRINT F(5)
RUN
QUIT
