-- TABLES two-way: a row with any crossing var missing is excluded entirely;
-- orphan levels (only ever co-occurring with a missing partner) are dropped.
USE "tests/data/freq_pm.csv"
TABLES REGION$*PRODUCT$
QUIT
