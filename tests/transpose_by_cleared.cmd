-- TRANSPOSE: the active BY list is cleared afterward.  The second TRANSPOSE with
-- no BY therefore treats all rows as a single block.
USE "tests/data/transpose_by_simple.csv"
BY grp$
TRANSPOSE /KEEP=score
DISPLAY
USE "tests/data/transpose_by_simple.csv"
TRANSPOSE /KEEP=score
DISPLAY
QUIT
