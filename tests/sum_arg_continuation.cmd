-- sdata#90: a function call's comma-delimited argument list must also
-- survive a trailing-comma continuation split, the same as USE's dataset
-- list -- both are comma-delimited grammars the old comma-discarding
-- continuation silently broke.
LET X = SUM(1, 2,
3, 4)
RUN
PRINT X
RUN
QUIT
