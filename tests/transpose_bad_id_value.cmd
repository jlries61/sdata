-- TRANSPOSE error #7: an /ID value is not a legal column identifier.
USE "tests/data/transpose_badid.csv"
TRANSPOSE /ID=id$
QUIT
