-- TRANSPOSE error #4: unknown variable in /KEEP (pre-exec error).
USE "tests/data/transpose_simple.csv"
TRANSPOSE /KEEP=nonexistent
QUIT
