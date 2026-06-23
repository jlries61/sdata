-- AGGREGATE after a committed data step: the deferred LET is RUN (which resets
-- the pending-deferred count), so AGGREGATE proceeds.  Exercises the batch-mode
-- RUN reset of the #10 guard.
USE "tests/data/sample.csv"
BY CATEGORY$
LET HOT = VAL1 > 5
RUN
AGGREGATE NHOT=SUM(HOT) NREC=N()
DISPLAY
QUIT
