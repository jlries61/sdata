-- UNSET /ALL removes an ordinary, already-committed temporary variable.
-- The SET must be committed by its own RUN first -- UNSET /ALL is
-- Immediate, so it acts on whatever is already defined at that moment, not
-- on a still-pending SET queued earlier in the same span (see RUN's row in
-- design.md for why).
NEW
USE MOCK
SET OTHERTEMP = 1
RUN
UNSET /ALL
PRINT OTHERTEMP
RUN
QUIT
