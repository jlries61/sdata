-- TRANSPOSE error #3: /NAME value must end in $ (parse-time error).
USE "tests/data/transpose_simple.csv"
TRANSPOSE /NAME=measure
QUIT
