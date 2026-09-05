-- Issue #117 / ADR-0024: USE on a dataset shaped with both a bare column Q
-- and its own subscripted siblings Q(1)/Q(2)/Q(3) must succeed (not abort
-- with "DIM cannot redefine scalar variable"), skip auto-registering Q as
-- an array, and leave every column individually reachable -- Q bare,
-- Q(n) via the backtick quoted-identifier form (design.md sec3.2), since
-- bare Q(n) syntax is unavoidably ambiguous with array/function-call
-- syntax once Q isn't a registered array.
USE "tests/data/use_subscripted_collision.csv"
PRINT Q `Q(1)` `Q(2)` `Q(3)`
RUN
QUIT
