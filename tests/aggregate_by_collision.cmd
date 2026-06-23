-- AGGREGATE error #8: an outvar collides with an active BY variable.
USE "tests/data/agg_runs.csv"
BY G
AGGREGATE G=SUM(V)
QUIT
