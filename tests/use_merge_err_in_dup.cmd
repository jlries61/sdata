-- Error test: two datasets request the same IN= provenance variable name.
-- Verifies that duplicate IN= names are detected and rejected.
USE "tests/data/merge_a.csv" (IN=both), "tests/data/merge_b.csv" (IN=both) /BY=ID
NEW
END
