-- PC-1 (2026-08-13 re-audit): reading past a virtual (ARRAY) array's
-- constituent count must raise, matching the real-array case
-- (array_element_read_oob.cmd) and Set_Array_Element's existing behavior.
LET A = 10
LET B = 20
LET C = 30
ARRAY V A B C
PRINT V(5)
RUN
QUIT
