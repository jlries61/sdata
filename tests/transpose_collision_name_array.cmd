-- TRANSPOSE error #10: an /ID-derived output column name collides with the
-- /NAME column name.
USE "tests/data/transpose_char.csv"
TRANSPOSE /ID=id$ /NAME=x$
QUIT
