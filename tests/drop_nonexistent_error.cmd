-- 2026-08-15: DROP naming a variable that doesn't exist as a table column
-- (a typo, or a session/temporary variable) must fail loudly rather than
-- silently no-op'ing. Milder consequence than the KEEP case (no data was
-- ever at risk here -- DROP only ever removes what it's told to), but the
-- same lack of feedback: previously the user had no way to tell a DROP had
-- done nothing. TEMP is a session variable, confirming DROP cannot be used
-- to remove one (that's UNSET's job).
NEW
USE MOCK
SET TEMP = 1
DROP TEMP
PRINT TEMP
RUN
QUIT
