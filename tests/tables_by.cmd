-- TABLES with BY: one frequency table per group; BY/SELECT intact afterward.
-- The second TABLES X$ proves BY is still active (print-only invariant).
USE "tests/data/freq_by.csv"
BY G$
TABLES X$
TABLES X$
QUIT
