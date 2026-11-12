-- F35: more than 16,384 columns cannot be addressed in a sheet (cell
-- references end at XFD); SAVE to .xlsx must fail up front.  The CSV is
-- generated at runtime (header + one row of 16,385 columns) and gitignored.
SYSTEM "seq 1 16385 | sed 's/^/c/' | paste -sd, - > tests/data/grid_limit_cols.csv && seq 1 16385 | paste -sd, - >> tests/data/grid_limit_cols.csv"
USE "tests/data/grid_limit_cols.csv"
SAVE "tests/data/grid_limit_cols.xlsx"
RUN
QUIT
