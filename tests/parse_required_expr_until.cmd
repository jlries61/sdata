-- REGRESSION: DO..UNTIL with no condition used to be accepted, leaving a null
-- condition in the AST, so the RUN below looped forever (the harness kills
-- it at 10 s). It must now be rejected at parse time, before RUN executes.
USE "tests/data/display_rows.csv"
RUN
DO
LET X = 1
UNTIL
RUN
QUIT
