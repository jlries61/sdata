-- sdata#90 BLOCKER-1 (04-code-review.md round 1): a trailing comma at the
-- end of a USE line, immediately followed by an unrelated next statement,
-- must raise a clear error rather than silently swallowing that statement
-- as a bogus second dataset spec (previously: USE "a.csv",\nQUIT\n opened
-- a nonexistent "QUIT.CSV" file and QUIT never ran).
USE "tests/data/freq.csv",
QUIT
