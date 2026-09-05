-- Issue #132 / ADR-0025: USE loading a literal column colliding with a
-- pre-existing (virtual) array must not let the stale array registration
-- shadow the freshly-loaded column's real data. Resolve_Column_Array_
-- Collisions removes the stale registration and PRINT Q must return the
-- loaded column's own value (99), not the old array's constituents.
LET A = 111
LET B = 222
ARRAY Q A B
RUN
USE "tests/data/array_collision_scalar.csv"
PRINT Q
RUN
QUIT
