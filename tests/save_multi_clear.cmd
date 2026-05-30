-- Multi-target SAVE clear semantics.
-- Step 1: register two targets, then clear with bare SAVE, then register one.
-- Only the single target registered last should be written.
USE "tests/data/merge_a.csv"
SAVE "tests/data/multi_out_p.csv", "tests/data/multi_out_q.csv"
SAVE
SAVE "tests/data/multi_out_r.csv"
RUN
NEW
END
