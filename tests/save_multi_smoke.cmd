-- Smoke test: multi-target SAVE writes both target files.
-- Both files should be created with the same table contents.
-- Simplified MVP: per-target IF= filtering deferred to Follow-on C.
USE "tests/data/merge_a.csv"
SAVE "tests/data/multi_out_p.csv", "tests/data/multi_out_q.csv"
PRINT ID, X
RUN
NEW
END
