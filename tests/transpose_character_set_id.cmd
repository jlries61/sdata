-- TRANSPOSE: character transposed set with /ID; output column names get a
-- trailing "$" appended to each /ID value.
USE "tests/data/transpose_char.csv"
TRANSPOSE /ID=id$
DISPLAY
QUIT
