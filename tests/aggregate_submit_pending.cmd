-- Regression for the SUBMIT / pending-deferred interaction: the outer LET is
-- still un-run after the SUBMITted sub-script's own RUN returns (SUBMIT
-- snapshots and restores Pending_Deferred around the nested Execute call,
-- so the sub-script's RUN cannot leak its reset out to the caller). Before
-- that fix, the sub-script's RUN cleared the shared pending counter and
-- AGGREGATE silently ran without the LET. Issue #70 / ADR-055: AGGREGATE no
-- longer errors on this (ADR-051's reject) -- it performs its own implicit
-- RUN first (the second "RUN complete" line below), correctly applying the
-- outer LET, then proceeds.
USE "tests/data/sample.csv"
BY CATEGORY$
LET HOT = VAL1 > 5
SUBMIT "tests/data/agg_submit_sub.cmd"
AGGREGATE NREC=N()
QUIT
