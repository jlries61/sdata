-- 2026-08-13 re-audit PC-4 / design.md sec3.4: DROP on a virtual array's
-- base name must delete all constituent variables along with the virtual
-- array definition itself ("If virtual array mentioned in DROP, all
-- constituent variables are deleted along with virtual array definition").
-- Previously DROP V matched nothing (V is never itself a table column) and
-- had zero effect.
LET A = 1
LET B = 2
LET C = 3
ARRAY V A B
DROP V
RUN
NAMES
ARRAY
QUIT
