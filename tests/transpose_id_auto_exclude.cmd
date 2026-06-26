-- TRANSPOSE: when the /ID column appears in /KEEP, it is silently auto-excluded
-- from the transposed set.
USE "tests/data/transpose_opts.csv"
TRANSPOSE /KEEP=id$ score height /ID=id$
DISPLAY
QUIT
