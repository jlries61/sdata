-- ADR-064: a backtick lex error typed interactively must cleanly reset the
-- REPL session (matching Run_REPL's existing Script_Error handler), not
-- crash the session and not silently drop the error. The session must
-- still work normally afterward.
SET X = 7
RUN
`bad
NOTE X
QUIT
