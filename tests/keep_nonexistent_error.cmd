-- 2026-08-15: KEEP naming a variable that doesn't exist as a table column
-- (a typo, or a session/temporary variable) must fail loudly, per
-- design.md's own promise -- previously unvalidated: an entirely-unmatched
-- Keep set silently dropped every real column instead of erring, since
-- "not in Keep" was the only condition Drop_Column checked. Atomic: the
-- NAMES call before RUN proves nothing was dropped by the rejected KEEP
-- (KEEP only takes effect at the next RUN in the first place, but the
-- validation itself also runs to completion before any column is touched).
NEW
USE MOCK
KEEP ID, BOGUS
NAMES
RUN
QUIT
