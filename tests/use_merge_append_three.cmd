-- APPEND: three datasets to verify multi-way concatenation.
-- merge_a (ID,X), merge_b (ID,Y), merge_c (ID,Z), 2 rows each -> 6 rows.
USE "tests/data/merge_a.csv", "tests/data/merge_b.csv", "tests/data/merge_c.csv" /APPEND
PRINT ID X Y Z
RUN
NEW
END
