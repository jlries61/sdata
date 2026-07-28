-- Issue #56: original repro. SET on a loaded column used to silently demote
-- it (dropping it from the table) and corrupt the subsequent SAVE output via
-- a PDV/table desync (Drop_Column mutating the table mid-record-loop). SET
-- must now fail loudly instead. Proof: SAVE's declarative execution only
-- stashes the pending target path/format (no message, no write); the actual
-- write AND the "Dataset saved" message both happen together, once, inside
-- Commit_Step, called only after RUN's per-record loop finishes every record
-- without error. SET's permanent-variable-redefinition check fires on the
-- very first record, aborting the loop before Commit_Step is ever reached --
-- hence no "Dataset saved" line and no output file below.
USE "tests/data/sample.csv"
SET VAL1 = VAL1 * 10
SAVE "tests/data/set_save_demotion_repro_out.csv"
RUN
