-- TRANSPOSE: the active SELECT filter is applied, then cleared.  The second
-- TRANSPOSE (no SELECT) sees all rows, proving the filter was consumed.
USE "tests/data/transpose_simple.csv"
SELECT score > 90
TRANSPOSE /ID=id$
DISPLAY
USE "tests/data/transpose_simple.csv"
TRANSPOSE /ID=id$
DISPLAY
QUIT
