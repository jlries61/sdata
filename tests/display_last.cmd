-- DISPLAY /LAST=<n>: print only the last n records, Obs showing each row's
-- REAL logical position (4, 5) -- not a 1..k relabel of the display order
-- (ADR-078's own explicitly-flagged design decision).
USE "tests/data/display_rows.csv"
RUN
DISPLAY /LAST=2
QUIT
