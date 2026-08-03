-- Issue #70 / ADR-055: TRANSPOSE with a pending (un-run) deferred statement
-- (formerly error #12, ADR-051's reject) now performs an implicit RUN first
-- (announcing itself exactly like an explicit RUN), then proceeds normally.
USE "tests/data/transpose_simple.csv"
LET x = score
TRANSPOSE /ID=id$
QUIT
