-- AGGREGATE: PCTL with an active BY group (ADR-075/sdata#93). Same groups
-- as stats_pctl_by.cmd: A={1,4} N=2 even, B={7,10,13} N=3 odd, C={16} N=1.
USE "tests/data/sample.csv"
BY CATEGORY$
AGGREGATE MED=PCTL(VAL1, 50)
DISPLAY
QUIT
