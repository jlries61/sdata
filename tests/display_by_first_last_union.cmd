-- /FIRST and /LAST combined with /BY=: the union is computed over the
-- /BY=-sorted order, not the original row order.
USE "tests/data/display_rows.csv"
RUN
DISPLAY ID SCORE /BY=SCORE /FIRST=2 /LAST=2
QUIT
