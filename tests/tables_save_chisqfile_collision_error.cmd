-- TABLES /SAVE /CHISQ: a BY variable named DF collides with the chi-square
-- file's computed DF column -- must raise a clear error (BLOCKER-1,
-- 04-code-review.md round 1). The main crosstab file has no such collision
-- (DF is not a request variable here) and is written normally before the
-- /CHISQ write fails -- same "main succeeds, chi-square fails" shape as
-- tables_save_refused.cmd. Saved under tests/data/ (gitignored, not
-- self-cleaned via SYSTEM rm) since the script aborts on the error below
-- the write, before any in-script cleanup could run -- same convention as
-- aggregate_save_flush_out.csv / save_drop.csv etc. An absolute /tmp path
-- was tried first but isn't portable: it is taken as a literal path by the
-- interpreter's own file I/O (not shell-expanded), and resolves to the
-- current drive's root on native Windows builds, which fails there.
USE "tests/data/tables_save_dfcollide.csv"
BY DF
TABLES REGION$*PRODUCT$ /CHISQ /SAVE="tests/data/tables_save_dfcollide_out.csv"
QUIT
