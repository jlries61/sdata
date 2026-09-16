-- /INTERLEAVE with per-dataset IF= on both specs (ADR-074/sdata#92).
-- merge_a_13.csv: ID=1,X=10 / ID=3,X=30 -- IF=X>=20 drops ID=1, keeps ID=3.
-- merge_b_24.csv: ID=2,Y=200 / ID=4,Y=400 -- IF=Y<400 keeps ID=2, drops ID=4.
-- Result: 2 rows in BY-sorted order (ID=2 from B, ID=3 from A), each with
-- one non-missing side -- confirms a filtered-out row never reaches
-- /INTERLEAVE's BY-sorted stacking.
USE "tests/data/merge_a_13.csv" (IF=X>=20), "tests/data/merge_b_24.csv" (IF=Y<400) /BY=ID /INTERLEAVE
PRINT ID X Y
RUN
NEW
END
