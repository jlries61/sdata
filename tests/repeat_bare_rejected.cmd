-- Issue #63 / ADR-054: REPEAT no longer accepts the pre-rename bare
-- REPEAT/UNTIL loop spelling (that loop is now DO/UNTIL) -- a bare REPEAT
-- with no record count must raise a clean, migration-specific error
-- rather than an internal Natural'Value crash.
LET I = 1
REPEAT
  LET I = I + 1
UNTIL I > 3
RUN
QUIT
