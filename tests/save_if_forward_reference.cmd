-- ADR-062/issue #76 regression: SAVE's IF= is checked once at target-
-- registration time for unknown-function/arity ONLY (Check_Undefined =>
-- False) -- not for undefined variables, since a temporary variable
-- referenced in IF= is legitimately defined by a LATER LET, evaluated
-- per-record before the first WRITE actually flushes this target. This
-- must keep working exactly as it did before the fix. Uses the two-target
-- form since that's the form proven to actually honor IF= per record
-- (see save_multi_with_if.cmd) -- unrelated single-target IF= filtering
-- gap filed separately, out of scope for this fix (issue TBD).
OPTIONS SAVEOVERWRT YES
USE "tests/data/merge_a.csv"
SAVE "tests/data/save_if_fwd_ref_big.csv" (IF=FLAG=1), "tests/data/save_if_fwd_ref_small.csv" (IF=FLAG=0)
LET FLAG = ID > 1
RUN
NEW
USE "tests/data/save_if_fwd_ref_big.csv"
PRINT ID, X
RUN
NEW
USE "tests/data/save_if_fwd_ref_small.csv"
PRINT ID, X
RUN
END
