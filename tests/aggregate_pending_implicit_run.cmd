-- Issue #70 / ADR-055: AGGREGATE with a pending (un-run) deferred statement
-- (formerly error #10, ADR-051's reject) now performs an implicit RUN first
-- (announcing itself exactly like an explicit RUN), then proceeds normally.
USE "tests/data/sample.csv"
BY CATEGORY$
LET HOT = VAL1 > 5
AGGREGATE NREC=N()
QUIT
