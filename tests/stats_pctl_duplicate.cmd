-- STATS: two PCTL entries with the SAME percentile collide on the same
-- output column name and are rejected explicitly rather than silently
-- dropping the second (ADR-075/sdata#93 -- Table.Add_Output_Column no-ops
-- on a duplicate name, which would otherwise misalign every later column).
USE "tests/data/sample.csv"
STATS VAL1 /STATS=PCTL(25) PCTL(25)
QUIT
