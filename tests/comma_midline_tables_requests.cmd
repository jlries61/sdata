-- ADR-080 D1: comma between TABLES requests
-- A mid-line comma in a comma-free position is a syntax error; a comma may only
-- end a line here. (Before, it was silently skipped.)
USE "tests/data/display_rows.csv"
RUN
TABLES ID, ID*ID
QUIT
