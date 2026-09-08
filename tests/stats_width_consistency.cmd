-- STATS: column widths are computed once, globally across the whole result
-- table, not per BY-group -- both groups' boxes must render with identical
-- column widths despite very different value magnitudes (systems-designer
-- 02-systems-designer.md, section 7 item 2).
USE "tests/data/stats_width_consistency.csv"
BY CAT$
STATS VAL /STATS=MEAN
QUIT
