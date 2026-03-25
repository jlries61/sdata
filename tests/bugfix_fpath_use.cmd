-- Test: FPATH /USE must take effect before subsequent USE in batch mode.
FPATH "tests/data/fpath_sub" /USE
USE SMALL
PRINT ID, VAL
RUN
FPATH
QUIT
