-- TABLES /SAVE /CHISQ: a BY variable named DF collides with the chi-square
-- file's computed DF column -- must raise a clear error (BLOCKER-1,
-- 04-code-review.md round 1). The main crosstab file has no such collision
-- (DF is not a request variable here) and is written normally before the
-- /CHISQ write fails -- same "main succeeds, chi-square fails" shape as
-- tables_save_refused.cmd. Saved under /tmp (not tests/data/) since the
-- script aborts on the error below the write, before any in-script cleanup
-- could run.
USE "tests/data/tables_save_dfcollide.csv"
BY DF
TABLES REGION$*PRODUCT$ /CHISQ /SAVE="/tmp/tables_save_dfcollide_out.csv"
QUIT
