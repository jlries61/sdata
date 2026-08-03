-- Issue #70 / ADR-055: TRANSPOSE placed immediately after REPEAT n (zero
-- pending statements, formerly rejected outright by ADR-051/#66) now
-- triggers an implicit RUN first, creating 4 records with zero columns.
-- TRANSPOSE then correctly errors on the empty column set (a real,
-- pre-existing TRANSPOSE validation, unrelated to #70) -- proving the
-- implicit-RUN trigger applies uniformly to TRANSPOSE too, not just
-- SORT/AGGREGATE.
NEW
REPEAT 4
TRANSPOSE
QUIT
