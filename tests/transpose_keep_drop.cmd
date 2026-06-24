-- TRANSPOSE: /KEEP and /DROP combined; effective set is KEEP minus DROP.
USE "tests/data/transpose_opts.csv"
TRANSPOSE /KEEP=score height weight /DROP=weight
DISPLAY
QUIT
