-- ADR-080 D2: a comment-only line after the comma is invisible; the
-- statement continues past it (only a blank line ends it).
PRINT 1,
-- a comment-only line
2
RUN
QUIT
