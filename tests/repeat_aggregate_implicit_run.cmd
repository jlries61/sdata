-- Issue #70 / ADR-055: AGGREGATE placed immediately after REPEAT n (before
-- any LET/SET is queued -- formerly rejected outright by ADR-051/#66) now
-- triggers an implicit RUN first, creating 6 records with zero columns.
-- Unlike repeat_sort_implicit_run_undefined.cmd's SORT X, NREC=N() needs no
-- input column, so it succeeds cleanly on the empty-body table -- the two
-- tests together show the implicit-RUN trigger is orthogonal to whether the
-- triggering command itself then succeeds or fails.
NEW
REPEAT 6
AGGREGATE NREC=N()
QUIT
