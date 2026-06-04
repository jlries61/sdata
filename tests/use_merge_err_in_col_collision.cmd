-- Error test: IN= name collides with a real column in the merged result.
-- Verifies that the executor raises Script_Error rather than overwriting data.
USE "tests/data/merge_a.csv" (IN=ID), "tests/data/merge_b.csv" (IN=Y) /BY=ID
NEW
END
