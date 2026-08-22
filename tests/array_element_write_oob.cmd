-- PC-1 (2026-08-13 re-audit) companion: Set_Array_Element's existing
-- out-of-bounds raise changed exception type (Program_Error -> Script_Error,
-- ADR-0014) as part of the same fix as Get_Array_Element's new raises.
-- Confirms the write path still cleanly reports the error and -k still
-- catches it, now that it's Script_Error rather than the old Program_Error.
DIM F(1 TO 3)
LET F(5) = 99
RUN
QUIT
