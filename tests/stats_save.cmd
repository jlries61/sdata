-- STATS: a pending SAVE is flushed when STATS executes.
USE "tests/data/sample.csv"
SAVE "tests/data/stats_save_test.csv"
STATS VAL1
QUIT
