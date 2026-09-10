-- DISPLAY: a SELECT filtering out every row still prints an empty box
-- (header + rule + rule, zero data rows) -- deliberately the OPPOSITE of
-- STATS' "(No rows to display)" message (ADR-068); see ADR-069.
USE "tests/data/sample.csv"
SELECT VAL1 > 1000
RUN
DISPLAY
QUIT
