-- TRANSPOSE: character transposed set with /ARRAY; the array name must carry
-- the "$" suffix to signal a character array.
USE "tests/data/transpose_char.csv"
TRANSPOSE /ARRAY=val$ /DROP=id$
DISPLAY
QUIT
