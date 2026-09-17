-- Two-way grid /NOPERCENT: 3-line row-blocks (Frequency, Row_Percent,
-- Col_Percent -- no Percent line) instead of the default 4. Confirms the
-- corner-legend and rule-line width computation adapt correctly when the
-- Percent statistic line is entirely absent, not just blank.
USE "tests/data/freq.csv"
TABLES REGION$*PRODUCT$ /NOPERCENT
QUIT
