-- ADR-080 D2: a blank line after a continuation comma ends the statement.
-- Before, the blank line was swallowed and PRINT 2 was glued onto PRINT 1,
-- producing a spurious error.
PRINT 1,

PRINT 2
RUN
QUIT
