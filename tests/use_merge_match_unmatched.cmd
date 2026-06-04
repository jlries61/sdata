-- Match merge full-outer with unmatched keys.
-- merge_a.csv: IDs 1,2  (X column)
-- merge_b_23.csv: IDs 2,3  (Y column)
-- Result: 3 rows; ID=1 has X but missing Y; ID=2 matched; ID=3 has Y but missing X.
USE "tests/data/merge_a.csv", "tests/data/merge_b_23.csv" /BY=ID
PRINT ID X Y
RUN
NEW
END
