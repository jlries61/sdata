-- Test FPATH command: set default directories for USE, SAVE, SUBMIT, OUTPUT
-- Set USE path to tests/data so we can SUBMIT without full path
FPATH "tests/data" / SUBMIT
SUBMIT "submit_sub.cmd"
RUN

-- Reset FPATH
FPATH

QUIT
