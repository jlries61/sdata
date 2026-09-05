-- ADR-066/issue #88: an unterminated string literal typed interactively
-- must cleanly reset the REPL session (matching Run_REPL's existing
-- Script_Error handler), not crash it and not silently drop the error.
-- The session must still work normally afterward.
SET X = 7
RUN
LET Y$ = "bad
NOTE X
QUIT
