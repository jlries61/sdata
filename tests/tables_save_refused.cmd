-- TABLES /SAVE honors OPTIONS SAVEOVERWRT: a refused overwrite prints one
-- clean error (not a second unhandled-exception-shaped line), TABLES
-- still reports complete, and the real table is unaffected.
USE "tests/data/freq.csv"
TABLES REGION$ /SAVE="tests/data/tables_save_refused_out.csv"
OPTIONS SAVEOVERWRT NO
TABLES REGION$ /SAVE="tests/data/tables_save_refused_out.csv"
DISPLAY
SYSTEM "rm -f tests/data/tables_save_refused_out.csv"
QUIT
