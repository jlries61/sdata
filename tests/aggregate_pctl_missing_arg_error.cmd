-- AGGREGATE: PCTL without its percentile argument must be a clear parse
-- error, not silently fall through to treating the last data value as the
-- percentile (ADR-075/sdata#93 -- a code-review-round catch: PCTL(ID) on an
-- integer-typed column whose last group value happens to fall in 0..100
-- silently computed a nonsensical result instead of raising anything).
USE MOCK
AGGREGATE T=PCTL(ID)
QUIT
