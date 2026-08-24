-- PD-2/ADR-058: a SUBMIT of the same file across multiple loop iterations
-- must warn exactly once (matching ADR-056's own per-occurrence, not
-- per-iteration, granularity for the direct case), not zero times (the
-- pre-fix bug) and not once per iteration (the naive-fix bug a fresh
-- re-parse-per-SUBMIT-call would otherwise cause -- see ADR-058's
-- Warned_Submit_Paths dedup). 5 iterations, not 1, specifically to
-- distinguish "once" from "once per invocation".
USE "tests/data/subscripted.csv"
FOR I = 1 TO 5
SUBMIT "tests/data/submit_declarative_sub.cmd"
NEXT I
RUN
QUIT
