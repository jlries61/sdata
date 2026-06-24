-- TRANSPOSE error #5: /ID column does not exist (pre-exec error).
USE "tests/data/transpose_simple.csv"
TRANSPOSE /ID=noexist
QUIT
