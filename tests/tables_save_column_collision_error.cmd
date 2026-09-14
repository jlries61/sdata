-- TABLES /SAVE: a crossing variable named FREQUENCY collides with the
-- computed Frequency column -- must raise a clear error (BLOCKER-1,
-- 04-code-review.md round 1), not silently drop the source data.
USE "tests/data/tables_save_collide.csv"
TABLES REGION$*FREQUENCY /SAVE="tests/data/tsc_collide_out.csv"
QUIT
