-- TRANSPOSE error #12: pending deferred program statements must be cleared first.
USE "tests/data/transpose_simple.csv"
LET x = score
TRANSPOSE /ID=id$
QUIT
