-- Issue #70 / ADR-055: STATS with a pending (un-run) deferred statement
-- (formerly error #12, ADR-051's reject) now performs an implicit RUN first
-- (announcing itself exactly like an explicit RUN), then proceeds normally.
USE "tests/data/sample.csv"
LET z = 1
STATS
QUIT
