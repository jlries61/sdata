-- NOTE (ADR-059): basic temporary-variable printing, same formatting as
-- PRINT. SET is Deferred, so RUN must fire before NOTE can see its value --
-- NOTE itself is Immediate and fires at its own position in program order.
SET X = 42
SET Y$ = "hello"
RUN
NOTE X
NOTE Y$
NOTE X Y$
QUIT
