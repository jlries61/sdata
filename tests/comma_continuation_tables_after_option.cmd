-- A continuation comma after a TABLES option (the option loop skips it).
USE "tests/data/display_rows.csv"
RUN
TABLES GROUP$ /NOCUM,
  /NOPERCENT
QUIT
