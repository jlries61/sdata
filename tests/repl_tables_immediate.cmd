-- Issue #69's motivating case: a direct regression guard reproducing the
-- shape of issue #68 (Stmt_TABLES missing from Is_Immediate caused the REPL
-- to silently queue a bare TABLES statement as if deferred, instead of
-- running it immediately). TABLES must produce output right after being
-- typed, with no RUN in between -- if Is_Immediate ever regresses for
-- TABLES (or any other Immediate-tier statement) again, QUIT would exit
-- with no TABLES output at all and this test would fail loudly instead of
-- silently, exactly the gap #69 reports make check cannot currently catch.
USE "tests/data/freq_select.csv"
TABLES PRODUCT$
QUIT
