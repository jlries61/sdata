-- STATS: N and NMISS correctly count present/missing values,
-- including empty string as missing for a character column.
-- stats_missing.csv has 4 rows; row 2 has missing NUM (.) and empty CHAR.
-- Expected: N=3 NMISS=1 for both variables; N+NMISS=4 in each case.
USE "tests/data/stats_missing.csv"
STATS NUM CHAR$ /STATS=N NMISS
QUIT
