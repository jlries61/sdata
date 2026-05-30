-- IN= variable per-row provenance: match merge (full outer BY=ID).
-- merge_a.csv:    ID=1 (X=10),  ID=2 (X=20)
-- merge_b_23.csv: ID=2 (Y=200), ID=3 (Y=300)
-- Row ID=1: only A contributed → hasA=1, hasB=0
-- Row ID=2: both contributed   → hasA=1, hasB=1
-- Row ID=3: only B contributed → hasA=0, hasB=1
USE "tests/data/merge_a.csv" (IN=hasA), "tests/data/merge_b_23.csv" (IN=hasB) /BY=ID
PRINT ID hasA hasB
RUN
NEW
END
