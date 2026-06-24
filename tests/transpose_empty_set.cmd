-- TRANSPOSE error #9: transposed set is empty after applying KEEP/DROP.
USE "tests/data/transpose_simple.csv"
TRANSPOSE /KEEP=id$ /DROP=id$
QUIT
