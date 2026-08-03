-- Issue #70 / ADR-055: SAVE + implicit RUN association. A registered SAVE
-- is one-shot -- Flush_Pending_Save (sdata-core) clears it immediately
-- after writing, so it is consumed by whichever commit point reaches it
-- first. REPEAT/LET/SAVE with no explicit RUN, then AGGREGATE (which
-- triggers an implicit RUN first): the implicit RUN suppresses its own
-- commit's SAVE flush (Suppress_Next_Save_Flush, ADR-055) so the
-- registration survives for AGGREGATE's own Commit_Reshaped_Table flush --
-- the saved file below reflects AGGREGATE's own result (TOTAL=10), not the
-- pre-aggregate table the implicit RUN produced. Confirmed empirically:
-- without the suppression, the implicit RUN's commit would have written
-- the pre-aggregate data and consumed the one-shot registration, leaving
-- AGGREGATE's own flush a silent no-op.
NEW
REPEAT 4
LET X = RECNO
SAVE "tests/data/repeat_save_implicit_run_out.csv"
AGGREGATE TOTAL=SUM(X)
NEW
USE "tests/data/repeat_save_implicit_run_out.csv"
DISPLAY
QUIT
