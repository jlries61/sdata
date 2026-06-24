-- TRANSPOSE error #11: /ARRAY name lacks "$" suffix for a character transposed set.
USE "tests/data/transpose_char.csv"
TRANSPOSE /ARRAY=vals /DROP=id$
QUIT
