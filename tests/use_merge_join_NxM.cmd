-- Cartesian join /BY=ID /JOIN with multi-row groups (N:M).
-- merge_a_nm.csv: ID=1 (2 rows: X=10,11), ID=2 (1 row: X=20)
-- merge_b_nm.csv: ID=1 (2 rows: Y=100,101), ID=2 (1 row: Y=200)
-- ID=1 group: 2x2=4 rows; ID=2 group: 1x1=1 row. Total: 5 rows.
USE "tests/data/merge_a_nm.csv", "tests/data/merge_b_nm.csv" /BY=ID /JOIN
PRINT ID X Y
RUN
NEW
END
