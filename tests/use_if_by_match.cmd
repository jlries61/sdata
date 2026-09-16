-- /BY= match-merge with per-dataset IF= on both specs (ADR-074/sdata#92).
-- merge_a_13.csv: ID=1,X=10 / ID=3,X=30 -- IF=X>=20 drops ID=1, keeps ID=3.
-- merge_b_23.csv: ID=2,Y=200 / ID=3,Y=300 -- IF=Y>=300 drops ID=2, keeps ID=3.
-- Both filters leave a single ID=3 row, so the match-merge produces one row.
USE "tests/data/merge_a_13.csv" (IF=X>=20), "tests/data/merge_b_23.csv" (IF=Y>=300) /BY=ID
PRINT ID X Y
RUN
NEW
END
