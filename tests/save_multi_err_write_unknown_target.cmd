-- Error test: WRITE names a target not present in Registered_Saves.
-- When multi-target SAVE is active, WRITE FOO must raise Script_Error
-- if FOO is not an alias or file path in the registered target list.
USE "tests/data/merge_a.csv"
SAVE "tests/data/out1.csv" AS A, "tests/data/out2.csv" AS B
WRITE FOO
RUN
NEW
END
