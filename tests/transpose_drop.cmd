-- TRANSPOSE: /DROP excludes columns from the transposed set.
USE "tests/data/transpose_opts.csv"
TRANSPOSE /DROP=id$ weight
DISPLAY
QUIT
