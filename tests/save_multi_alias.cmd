-- Multi-target SAVE with AS alias syntax.
-- Verifies that aliases parse correctly and both targets are written.
-- Alias-based WRITE routing is Follow-on C; here we verify parse + flush.
USE "tests/data/merge_a.csv"
SAVE "tests/data/multi_out_p.csv" AS P, "tests/data/multi_out_q.csv" AS Q
PRINT ID, X
RUN
NEW
END
