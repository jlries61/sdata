-- DISPLAY <varlist>: same as display_select_no_run.cmd but for the
-- varlist form of DISPLAY, which is a separate surface (both funnel
-- through the shared Display_Table renderer, but a fix landing on only
-- one path would leave this one still broken) (sdata#89 / ADR-070).
USE "tests/data/sample.csv"
SELECT VAL1 > 5
DISPLAY CATEGORY$ VAL1
QUIT
