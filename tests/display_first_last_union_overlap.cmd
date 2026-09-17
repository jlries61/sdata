-- /FIRST and /LAST together where the two ranges overlap (in fact
-- cover the whole 5-row table): the union must deduplicate, showing
-- each row exactly once rather than repeating the overlapping rows.
USE "tests/data/display_rows.csv"
RUN
DISPLAY /FIRST=3 /LAST=3
QUIT
