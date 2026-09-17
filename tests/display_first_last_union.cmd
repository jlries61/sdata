-- /FIRST and /LAST together in one statement (ADR-078, revised): the
-- result is the UNION of the first n and last m records, not an error
-- and not a slice -- here the ranges don't overlap, so all 4 selected
-- rows are distinct with no separator between the two blocks.
USE "tests/data/display_rows.csv"
RUN
DISPLAY /FIRST=2 /LAST=2
QUIT
