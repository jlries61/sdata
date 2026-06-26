-- TRANSPOSE: no BY, /ID; ID values become output column names.
USE "tests/data/transpose_simple.csv"
TRANSPOSE /ID=id$
DISPLAY
QUIT
