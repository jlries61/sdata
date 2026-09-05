-- ADR-0025 + ADR-0024 combined: the loaded file is ADR-0024's own
-- collision shape (a bare column Q alongside its own subscripted siblings
-- Q(1)/Q(2)/Q(3)) AND Q is *also* a pre-existing, unrelated array. Both
-- reconciliation passes must fire, in order, without a contradictory or
-- redundant message -- Resolve_Column_Array_Collisions removes the stale
-- array first, so Register_Subscripted_Columns's own notice correctly
-- reports Q as "a scalar variable" (not "an array"), since by the time it
-- runs the array is already gone.
LET A = 111
LET B = 222
ARRAY Q A B
RUN
USE "tests/data/array_collision_combined.csv"
PRINT Q `Q(1)` `Q(2)` `Q(3)`
RUN
QUIT
