-- ADR-0025's second call site: Commit_Reshaped_Table (shared by AGGREGATE/
-- TRANSPOSE/STATS) replaces the in-memory table the same way USE does, so
-- an outvar name colliding with a pre-existing, unrelated array must be
-- resolved the same way. AGGREGATE's own pre-existing "resizing existing
-- variable" notice (shape-change awareness) is expected to also fire --
-- it answers a different question (outvar shape changed) than
-- Resolve_Column_Array_Collisions (stale Array_Symbols entry removed) and
-- both are correct, non-redundant, non-contradictory.
LET A = 111
LET B = 222
ARRAY Q A B
RUN
USE "tests/data/array_collision_aggregate.csv"
BY GRP
AGGREGATE Q=SUM(X)
DISPLAY
QUIT
