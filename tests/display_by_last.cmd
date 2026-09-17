-- /BY= composed with /LAST=: sort happens BEFORE truncation (ADR-078's
-- only sensible composition order) -- the last 2 of the SCORE-sorted
-- order, not the last 2 of the original row order.
USE "tests/data/display_rows.csv"
RUN
DISPLAY ID SCORE /BY=SCORE /LAST=2
QUIT
