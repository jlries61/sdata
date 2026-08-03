-- Issue #70 / ADR-055: SAVE + implicit RUN association via the REPL path
-- specifically -- Ensure_Pending_Flushed's Run_Active_Program branch (a
-- pending LET queued in Active_Program_Vec) is a different code path from
-- the batch-style Step_Start flush repeat_save_implicit_run.cmd covers, but
-- both must consume the same Suppress_Next_Save_Flush flag so the
-- registered SAVE survives for SORT's own Execute_Commit_Step flush,
-- writing the sorted result (1,2,3,4), not the pre-sort table.
USE "tests/data/freq_select.csv"
LET Z = ID * -1
SAVE "tests/data/repl_implicit_run_save_out.csv"
SORT Z
NEW
USE "tests/data/repl_implicit_run_save_out.csv"
DISPLAY
QUIT
