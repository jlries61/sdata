-- TRANSPOSE: /NAME overrides the default _NAME_$ column name.
USE "tests/data/transpose_opts.csv"
TRANSPOSE /KEEP=score height /ID=id$ /NAME=measure$
DISPLAY
QUIT
