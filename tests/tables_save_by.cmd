-- TABLES /SAVE with an active BY: one combined file, BY columns leading
-- (matching STATS/AGGREGATE's own convention), one row set per group.
USE "tests/data/freq.csv"
BY REGION$
TABLES PRODUCT$ /SAVE="tests/data/tables_save_by_out.csv"
SYSTEM "cat tests/data/tables_save_by_out.csv"
SYSTEM "rm -f tests/data/tables_save_by_out.csv"
QUIT
