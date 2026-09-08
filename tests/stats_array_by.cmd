-- STATS: whole-array expansion combined with an active BY. No existing
-- fixture combined array-subscripted columns with a BY-groupable category
-- (systems-designer 02-systems-designer.md, finding #1) -- new fixture.
USE "tests/data/stats_array_by.csv"
BY CAT$
STATS X
QUIT
