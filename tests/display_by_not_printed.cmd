-- DISPLAY /BY= naming a variable that is NOT among the printed columns
-- (the brief's own explicit ask: "which need not be among those printed").
-- Confirms By_Cols and Cols are independent -- sorting by SCORE while only
-- printing ID.
USE "tests/data/display_rows.csv"
RUN
DISPLAY ID /BY=SCORE
QUIT
