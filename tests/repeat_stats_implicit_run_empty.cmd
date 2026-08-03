-- Issue #70 / ADR-055: STATS placed immediately after REPEAT n (zero
-- pending statements, formerly rejected outright by ADR-051/#66) now
-- triggers an implicit RUN first, creating 4 records with zero columns.
-- STATS then correctly errors on the empty variable set (a real,
-- pre-existing STATS validation, unrelated to #70) -- proving the
-- implicit-RUN trigger applies uniformly to STATS too, not just
-- SORT/AGGREGATE.
NEW
REPEAT 4
STATS
QUIT
