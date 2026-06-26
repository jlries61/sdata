-- TRANSPOSE: BY + /ARRAY; blocks have different sizes; max-K bound used; short
-- blocks show "." for positions beyond their row count.
USE "tests/data/transpose_by_uneven.csv"
BY class$
TRANSPOSE
DISPLAY
QUIT
