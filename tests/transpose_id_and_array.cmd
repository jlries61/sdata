-- TRANSPOSE error #1: /ID and /ARRAY are mutually exclusive (parse-time error).
USE "tests/data/transpose_simple.csv"
TRANSPOSE /ID=id$ /ARRAY=vals
QUIT
