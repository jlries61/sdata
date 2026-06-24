-- TRANSPOSE error #6: two rows in the same BY block share an /ID value.
USE "tests/data/transpose_dupid.csv"
BY group$
TRANSPOSE /ID=id$
QUIT
