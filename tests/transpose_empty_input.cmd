-- TRANSPOSE: when SELECT matches no rows, the output table has the correct
-- schema but zero rows; no error is raised.
USE "tests/data/transpose_simple.csv"
SELECT score > 1000
TRANSPOSE /ID=id$
DISPLAY
QUIT
