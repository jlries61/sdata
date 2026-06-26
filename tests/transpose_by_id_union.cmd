-- TRANSPOSE: BY + /ID; blocks have different ID sets; output uses the union,
-- missing positions shown as ".".
USE "tests/data/transpose_by.csv"
BY class$
TRANSPOSE /ID=id$
DISPLAY
QUIT
