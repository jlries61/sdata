-- IN= variable per-row provenance: interleave merge.
-- merge_a_13.csv: ID=1 (X=10), ID=3 (X=30)
-- merge_b_24.csv: ID=2 (Y=200), ID=4 (Y=400)
-- Interleave emits one row at a time from the input with the smallest key.
-- Row ID=1: from A → hasA=1, hasB=0
-- Row ID=2: from B → hasA=0, hasB=1
-- Row ID=3: from A → hasA=1, hasB=0
-- Row ID=4: from B → hasA=0, hasB=1
USE "tests/data/merge_a_13.csv" (IN=hasA), "tests/data/merge_b_24.csv" (IN=hasB) /BY=ID /INTERLEAVE
PRINT ID hasA hasB
RUN
NEW
END
