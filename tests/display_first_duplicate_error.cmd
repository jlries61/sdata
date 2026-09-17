-- /FIRST repeated in one statement is still an error, worded as a
-- duplicate-option error (not a mutual-exclusion error -- /FIRST and
-- /LAST may both be given at once, see display_first_last_union.cmd;
-- this tests the SAME flag given twice, ADR-078).
USE "tests/data/display_rows.csv"
RUN
DISPLAY /FIRST=5 /FIRST=3
QUIT
