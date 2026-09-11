-- DISPLAY: a bare DISPLAY issued right after SELECT, with NO intervening RUN,
-- must still reflect the SELECT filter (sdata#89 / ADR-070) -- not the
-- unfiltered table.  Compare display_empty_box.cmd, which has the same
-- shape but with a RUN present.
USE "tests/data/sample.csv"
SELECT VAL1 > 5
DISPLAY
QUIT
