-- PC-3 (2026-08-13 re-audit, expanded during investigation): ARRAY must
-- reject replacing an existing real (DIM'd) array, per design.md's own
-- ARRAY command-reference row ("If an actual array with the name specified
-- already exists then the command shall fail with an error message").
-- Previously silently succeeded and orphaned Q's data columns. Q's original
-- data must be provably intact after the rejected ARRAY attempt.
DIM Q(1 TO 3)
LET Q(1) = 10
LET Q(2) = 20
LET Q(3) = 30
RUN
PRINT Q(1) Q(2)
LET A = 1
LET B = 2
ARRAY Q A B
RUN
NAMES
QUIT
