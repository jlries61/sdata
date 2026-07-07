-- AGGREGATE: a pending SAVE is written and then cleared.  The trailing USE +
-- RUN (no SAVE) must not re-save, proving the pending SAVE was consumed.
USE "tests/data/sample.csv"
BY CATEGORY$
SAVE "tests/data/aggregate_save_flush_out.csv"
AGGREGATE TOTAL=SUM(VAL1) NREC=N()
DISPLAY
QUIT
