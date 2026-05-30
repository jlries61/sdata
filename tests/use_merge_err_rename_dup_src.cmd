-- Error test: RENAME= with duplicate source variable name (ID=X, ID=Y).
-- Verifies that Apply_Rename detects and reports the duplicate.
USE "tests/data/merge_a.csv" (RENAME=(ID=X, ID=Y)), "tests/data/merge_b.csv" /BY=ID2
QUIT
