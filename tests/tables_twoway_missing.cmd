-- TABLES two-way /MISSING: "." is a valid level in both margins; all 7 rows
-- counted; grand=7; no "Frequency Missing" line.
USE "tests/data/freq_pm.csv"
TABLES REGION$*PRODUCT$ /MISSING
QUIT
