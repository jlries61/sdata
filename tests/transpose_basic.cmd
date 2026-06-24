-- TRANSPOSE: no BY, no /ID; default /ARRAY=_X_, /DROP to exclude the character column.
USE "tests/data/transpose_simple.csv"
TRANSPOSE /DROP=id$
DISPLAY
QUIT
