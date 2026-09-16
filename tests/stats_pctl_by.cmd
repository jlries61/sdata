-- STATS: PCTL(<p>) with an active BY group, covering odd N (group B, N=3),
-- even N (group A, N=2), and the N=1 degenerate case (group C) -- every
-- percentile of a single value is that value, regardless of p.
USE "tests/data/sample.csv"
BY CATEGORY$
STATS VAL1 /STATS=N PCTL(50)
QUIT
