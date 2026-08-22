-- PC-3 (systems-designer recommendation): USE's Register_Subscripted_Columns
-- auto-detection (ADR-041) now inherits DIM's virtual-array-replacement
-- fix -- a base(n)-shaped column pattern that collides with a pre-existing
-- virtual array silently replaces it (per ADR-0015), which used to crash
-- before this fix. Confirms the added one-line notice (matching
-- Execute_AGGREGATE's Warn_Resizing precedent) makes that replacement
-- visible instead of silent, and that the load still succeeds.
LET P = 1
LET Q = 2
ARRAY X P Q
USE "tests/data/subscripted.csv"
RUN
NAMES
QUIT
