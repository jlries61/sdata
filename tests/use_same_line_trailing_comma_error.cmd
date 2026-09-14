-- sdata#90 BLOCKER-1: the pre-existing same-line variant of the same
-- defect (USE "a.csv", QUIT on one line, no continuation involved at
-- all) -- now also caught by the same guard, as a welcome side effect.
USE "tests/data/freq.csv", QUIT
