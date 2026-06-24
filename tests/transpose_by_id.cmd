-- TRANSPOSE: BY + /ID with the same ID set in every block.
USE "tests/data/transpose_by_same.csv"
BY class$
TRANSPOSE /ID=id$
DISPLAY
QUIT
