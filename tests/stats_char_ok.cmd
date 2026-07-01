-- STATS: N and NMISS are valid on a character column.
USE "tests/data/sample.csv"
STATS CATEGORY$ /STATS=N NMISS
QUIT
