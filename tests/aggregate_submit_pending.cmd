-- Regression for the SUBMIT / pending-deferred interaction: the outer LET is
-- un-run, so AGGREGATE must raise #10 even though the SUBMITted sub-script ends
-- in a RUN.  Before the fix, the sub-script's RUN cleared the shared pending
-- counter and AGGREGATE silently ran without the LET.
USE "tests/data/sample.csv"
BY CATEGORY$
LET HOT = VAL1 > 5
SUBMIT "tests/data/agg_submit_sub.cmd"
AGGREGATE NREC=N()
QUIT
