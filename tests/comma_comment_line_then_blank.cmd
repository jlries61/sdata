-- ADR-080 D2: a comment line is skipped, but a blank line after it still ends
-- the statement.
PRINT 1,
-- a comment-only line

PRINT 2
RUN
QUIT
