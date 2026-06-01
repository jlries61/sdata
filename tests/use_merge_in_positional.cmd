-- IN= variable per-row provenance: positional merge.
-- merge_a.csv has 2 rows, merge_b.csv has 2 rows.
-- Positional: both inputs contribute to every output row.
-- hasA and hasB must both be 1 for all 2 rows.
USE "tests/data/merge_a.csv" (IN=hasA), "tests/data/merge_b.csv" (IN=hasB)
PRINT hasA hasB
RUN
NEW
END
