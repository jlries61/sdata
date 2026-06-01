-- Match merge /BY=ID, 1:1 case: merge_a (ID,X) and merge_b (ID,Y).
-- Both have IDs 1 and 2; result is 2 rows with X and Y merged.
USE "tests/data/merge_a.csv", "tests/data/merge_b.csv" /BY=ID
PRINT ID X Y
RUN
NEW
END
