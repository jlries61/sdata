-- Error test: assigning to an IN= variable via LET is rejected.
-- Verifies that IN= provenance variables are read-only from user code.
USE "tests/data/merge_a.csv" (IN=hasA), "tests/data/merge_b.csv" (IN=hasB) /BY=ID
LET hasA = 99
RUN
NEW
END
