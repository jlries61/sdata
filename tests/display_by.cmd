-- DISPLAY /BY=<varlist>: sorts the printed order by SCORE (ascending),
-- Obs showing each row's real logical position in the ORIGINAL, unsorted
-- table (2, 5, 3, 1, 4) -- confirms the sort never renumbers Obs.
USE "tests/data/display_rows.csv"
RUN
DISPLAY ID GROUP$ SCORE /BY=SCORE
QUIT
