-- TABLES honors an active SELECT filter (regression test for the dropped
-- Rebuild_Filter_Map).  ID < 4 selects the three East rows only, so PRODUCT$
-- must tabulate A=2, B=1, Total=3 -- NOT the whole-table A=3, B=3, Total=6.
-- (SELECT filters use sdata-core's Parse_Expression, whose lexer does not
-- accept '$' column names, so the filter is on the numeric ID column.)
USE "tests/data/freq_select.csv"
SELECT ID < 4
TABLES PRODUCT$
QUIT
