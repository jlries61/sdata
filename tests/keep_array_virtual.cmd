-- 2026-08-13 re-audit PC-4: KEEP on a virtual array's base name must retain
-- all of its constituent variables (design.md sec3.4: "If virtual array
-- mentioned in KEEP, all constituent variables are retained"). Previously
-- KEEP V matched nothing (V is never itself a table column), so it dropped
-- everything -- including A and B, the constituents KEEP was supposed to
-- save.
LET A = 1
LET B = 2
LET C = 3
ARRAY V A B
KEEP V
RUN
NAMES
QUIT
