-- ADR-080 D1 counterpart: a comma that ENDS a line is still a legal continuation
-- in every comma-free position (only a mid-line comma became an error).
-- STATS goes last because it replaces the data table.
USE "tests/data/display_rows.csv"
RUN
TABLES GROUP$,
  /NOCUM
DISPLAY ID,
  /FIRST=1,
  /LAST=1
STATS ID,
  /STATS=N
QUIT
