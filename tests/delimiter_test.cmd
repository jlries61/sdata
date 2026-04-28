-- Test pipe delimiter (single char)
USE "tests/data/pipe_delim.csv" / DLM=|
PRINT NAME$ SCORE
RUN

-- Test tab delimiter via keyword
USE "tests/data/tab_delim.csv" / DLM=TAB
PRINT NAME$ SCORE
RUN

-- Test two-character delimiter "||"
USE "tests/data/dblpipe_delim.csv" / DLM=||
PRINT NAME$ SCORE
RUN

-- Test pipe round-trip: write with pipe, read back with pipe
USE "tests/data/sample.csv" / DLM=COMMA
SAVE "tests/data/output_pipe.csv" / DLM=|
RUN
USE "tests/data/output_pipe.csv" / DLM=|
PRINT CATEGORY$ VAL1 VAL2 VAL3
RUN

END
