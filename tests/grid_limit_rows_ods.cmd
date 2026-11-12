-- F35: a table with more rows than the sheet grid holds (1,048,576 including
-- the header row) must make SAVE to .ods fail up front, not write a file that
-- Excel / LibreOffice refuse or truncate.  Exactly at the limit (1,048,575
-- data rows) is covered by the Write path; this checks one row over.
REPEAT 1048576
LET X = RECNO
RUN
SAVE "tests/data/grid_limit_rows.ods"
RUN
QUIT
