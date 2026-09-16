-- AGGREGATE: a second, comma-separated argument to any function OTHER than
-- PCTL must be a clear parse error (ADR-075/sdata#93 -- a code-review-round
-- catch: without this check, SUM(x, 5) silently computed SUM(x)+5, since
-- Handle_Sum has no concept of a trailing percentile sentinel and folds
-- whatever Emit_Group appends into its own sum).
USE MOCK
AGGREGATE T=SUM(SALARY, 5)
QUIT
