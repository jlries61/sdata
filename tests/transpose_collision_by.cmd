-- TRANSPOSE error #10: output column name collides with the active BY variable.
USE "tests/data/transpose_by_uneven.csv"
BY class$
TRANSPOSE /NAME=class$
QUIT
