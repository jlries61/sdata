-- STATS: BY grouping produces one row per (group x variable).
USE "tests/data/sample.csv"
BY CATEGORY$
STATS VAL1
QUIT
