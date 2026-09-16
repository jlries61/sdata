-- AGGREGATE: PCTL applied to a whole registered array, element-wise
-- (ADR-075/sdata#93). x(1)=[1,4] x(2)=[2,5] x(3)=[3,6] across the 2 records
-- -- median of each 2-element column equals its mean (same fixture and
-- comparison MEAN already uses in aggregate_array_input.cmd).
USE "tests/data/subscripted.csv"
AGGREGATE PX=PCTL(X, 50) MX=MEAN(X)
DISPLAY
QUIT
