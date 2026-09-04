-- ADR-062/issue #76: SAVE's per-target IF= expression is now checked once
-- at target-registration time, not silently on every record. An unknown
-- function in IF= raises the clean "unknown function" error at the SAVE
-- statement itself, not a per-record silent mis-filter.
USE "tests/data/merge_a.csv"
SAVE "tests/data/save_if_unknown_fn_out.csv" (IF=BOGUSFUNC(1)), "tests/data/save_if_unknown_fn_out2.csv" (IF=1)
RUN
QUIT
