-- ADR-0024 sweeps both storage classes Dim_Array itself guards against, not
-- just the literal-loaded-column case issue #117's own reproduction shows:
-- a pre-existing genuine temporary (SET) variable named Q, still in scope
-- when USE loads a file whose columns are only Q(1)/Q(2)/Q(3) (no bare Q
-- column at all), hits the identical Dim_Array rejection today and must be
-- guarded the same way. Q must keep its pre-existing temporary value (5)
-- after USE, unaffected by the loaded file.
REPEAT 1
SET Q = 5
RUN
USE "tests/data/use_subscripted_collision_temp.csv"
PRINT Q `Q(1)` `Q(2)` `Q(3)`
RUN
QUIT
