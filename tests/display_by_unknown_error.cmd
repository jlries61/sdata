-- /BY= naming an unknown column: a clean runtime error, not a silent
-- no-op (matching TABLES's own "unknown variable" precedent) -- a
-- deliberate, new-code-only stricter convention than the printed
-- varlist's own pre-existing silent-degrade behavior (ADR-078).
USE "tests/data/display_rows.csv"
RUN
DISPLAY /BY=NOPE
QUIT
