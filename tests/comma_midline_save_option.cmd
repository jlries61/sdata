-- ADR-080 D1: comma between SAVE options
-- A mid-line comma in a comma-free position is a syntax error; a comma may only
-- end a line here. (Before, it was silently skipped.)
SAVE "tests/data/comma_never_written.csv" /HEADER=YES, /HEADER=NO
QUIT
