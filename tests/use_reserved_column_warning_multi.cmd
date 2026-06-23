-- Multi-dataset USE whose merged schema contains reserved-keyword columns.
-- reserved_cols.csv: ID,AS,USE (rows 1,10,100 / 2,20,200).
-- APPEND of the file with itself gives a 3-column schema (ID,AS,USE) with
-- 4 rows.  The warning must fire exactly once per reserved column in the
-- MERGED schema -- not once per input dataset (which would be 4 warnings).
USE "tests/data/reserved_cols.csv", "tests/data/reserved_cols.csv" /APPEND
PRINT ID `AS` `USE`
RUN
NEW
END
