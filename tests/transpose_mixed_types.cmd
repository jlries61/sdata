-- TRANSPOSE error #8: the transposed set mixes numeric and character columns.
USE "tests/data/transpose_opts.csv"
TRANSPOSE /KEEP=score id$
QUIT
