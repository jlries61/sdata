-- F35: exactly 16,384 columns (the last is XFD) is within the grid and must
-- still save to XLSX and ODS and read back intact.
SYSTEM "seq 1 16384 | sed 's/^/c/' | paste -sd, - > tests/data/grid_limit_ok.csv && seq 1 16384 | paste -sd, - >> tests/data/grid_limit_ok.csv"
USE "tests/data/grid_limit_ok.csv"
SAVE "tests/data/grid_limit_ok.xlsx"
RUN
USE "tests/data/grid_limit_ok.xlsx"
PRINT "xlsx c1=" C1 "c16384=" C16384
RUN
USE "tests/data/grid_limit_ok.csv"
SAVE "tests/data/grid_limit_ok.ods"
RUN
USE "tests/data/grid_limit_ok.ods"
PRINT "ods c1=" C1 "c16384=" C16384
RUN
QUIT
