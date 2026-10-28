-- F51 regression: under OUTPUT /CHARSET=ASCII a non-ASCII character fails
-- instead of being written unchanged (as SAVE/USE already do).
OUTPUT "tests/data/output_ascii_rej.txt" /CHARSET=ASCII
PRINT "h" + "é"
RUN
QUIT
