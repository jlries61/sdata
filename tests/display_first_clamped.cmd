-- /FIRST=<n> larger than the actual row count clamps to however many rows
-- exist rather than erroring (matches USE /MAXROWS='s own "cap, don't
-- error" precedent).
USE "tests/data/display_rows.csv"
RUN
DISPLAY /FIRST=100
QUIT
