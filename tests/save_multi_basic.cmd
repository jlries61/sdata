-- Basic multi-target SAVE: two targets both receive the committed table.
-- Verifies that both files are written at end of RUN.
USE "tests/data/merge_a.csv"
SAVE "tests/data/multi_out_p.csv", "tests/data/multi_out_q.csv"
RUN
NEW
END
