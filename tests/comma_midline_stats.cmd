-- ADR-080 D1: STATS varlist then comma then option
-- A mid-line comma in a comma-free position is a syntax error; a comma may only
-- end a line here. (Before, it was silently skipped.)
USE "tests/data/display_rows.csv"
RUN
STATS ID, /STATS=N
QUIT
