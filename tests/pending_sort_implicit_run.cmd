-- Issue #70 / ADR-055: SORT with a pending (un-run) deferred statement and
-- no REPEAT involved at all -- SORT never had its own individual
-- Pending_Deferred guard (only Repeat_Active, via ADR-051/#66's
-- Reject_If_Repeat_Active); this is the plain "just forgot to RUN" case.
-- The implicit RUN applies the LET, then SORT runs against the up-to-date
-- table.
USE "tests/data/freq_select.csv"
LET Z = ID * -1
SORT Z
PRINT ID Z
RUN
QUIT
