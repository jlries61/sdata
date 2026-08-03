-- Issue #69: a script error raised by an Immediate-tier command mid-session
-- must not crash Run_REPL or leave it stuck -- the buffer resets and the
-- REPL keeps accepting input afterward. TABLES on an unknown crossing
-- variable errors immediately; the subsequent PRINT/RUN/TABLES sequence
-- proves the REPL's own exception handler (not batch's Execute) recovered
-- cleanly and state (Pending_Deferred etc.) is still consistent.
USE "tests/data/freq_select.csv"
TABLES NOPE$
PRINT "still alive"
RUN
TABLES PRODUCT$
QUIT
