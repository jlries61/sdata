-- TRANSPOSE: a pending SAVE is written immediately, then cleared.
USE "tests/data/transpose_simple.csv"
SAVE "tests/data/transpose_save_flush_out.csv"
TRANSPOSE /ID=id$
DISPLAY
QUIT
