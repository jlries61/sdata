-- Per-target KEEP/DROP/RENAME on multi-target SAVE (Follow-on B).
-- merge_a.csv has columns: ID, X
-- save_keep.csv  should have only ID
-- save_drop.csv  should have only X (ID dropped)
-- save_rename.csv should have ID, Y (X renamed to Y)
OPTIONS SAVEOVERWRT YES
USE "tests/data/merge_a.csv"
SAVE "tests/data/save_keep.csv" (KEEP=ID), "tests/data/save_drop.csv" (DROP=ID), "tests/data/save_rename.csv" (RENAME=(X=Y))
RUN
NEW
USE "tests/data/save_keep.csv"
NAMES
NEW
USE "tests/data/save_drop.csv"
NAMES
NEW
USE "tests/data/save_rename.csv"
NAMES
NEW
END
