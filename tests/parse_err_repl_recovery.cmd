-- ADR-060: a parse error typed interactively must cleanly reset the REPL
-- session (matching Run_REPL's existing Script_Error handler), not crash
-- the session and not silently execute the malformed statement. The
-- session must still work normally afterward.
SET X = 7
RUN
LET Y = 1 +
NOTE X
QUIT
