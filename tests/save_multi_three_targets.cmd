-- Three-target SAVE: verify all three files are written at end of RUN.
USE "tests/data/merge_a.csv"
SAVE "tests/data/multi_out_p.csv", "tests/data/multi_out_q.csv", "tests/data/multi_out_r.csv"
RUN
NEW
END
