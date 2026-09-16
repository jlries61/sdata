-- STATS: PCTL(<p>) inside /STATS=, multiple percentiles alongside ordinary
-- statistics (ADR-075/sdata#93). VAL1 sorted: 1,4,7,10,13,16 (N=6, even).
-- Hand-verified: PCTL0=1 (min, exact), PCTL25=4.75 (interpolated),
-- MEDIAN=8.5, PCTL75=12.25 (interpolated), PCTL100=16 (max, exact).
USE "tests/data/sample.csv"
STATS VAL1 /STATS=N MIN PCTL(0) PCTL(25) MEDIAN PCTL(75) PCTL(100) MAX
QUIT
