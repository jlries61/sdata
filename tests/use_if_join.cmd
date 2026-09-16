-- /JOIN (Cartesian, within BY group) with per-dataset IF= (ADR-074/sdata#92).
-- merge_a_nm.csv: ID=1 (X=10,11), ID=2 (X=20) -- IF=X<>11 drops the X=11 row,
-- leaving ID=1 (X=10 only), ID=2 (X=20).
-- merge_b_nm.csv: ID=1 (Y=100,101), ID=2 (Y=200) -- no filter.
-- Without the filter this would be a 2x2=4 + 1x1=1 = 5-row join (see
-- use_merge_join_NxM.cmd); with X=11 filtered out of A, ID=1 becomes a
-- 1x2=2-row group instead, for 3 rows total -- confirms the filter is
-- applied before the Cartesian expansion, not after.
USE "tests/data/merge_a_nm.csv" (IF=X<>11), "tests/data/merge_b_nm.csv" /BY=ID /JOIN
PRINT ID X Y
RUN
NEW
END
