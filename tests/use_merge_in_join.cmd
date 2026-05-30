-- IN= variable per-row provenance: inner join.
-- merge_a.csv: ID=1 (X=10), ID=2 (X=20)
-- merge_b.csv: ID=1 (Y=100), ID=2 (Y=200)
-- /JOIN inner join: only fully-matched groups emit rows.
-- Both inputs contribute to every output row → hasA=1, hasB=1 always.
USE "tests/data/merge_a.csv" (IN=hasA), "tests/data/merge_b.csv" (IN=hasB) /BY=ID /JOIN
PRINT ID hasA hasB
RUN
NEW
END
