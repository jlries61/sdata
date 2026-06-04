-- Error test: per-dataset RENAME with two pairs targeting the same new name.
-- Verifies Apply_Rename detects and reports the duplicate target.
-- Two datasets are needed to trigger the multi-dataset USE path.
USE "tests/data/merge_a.csv" (RENAME=(ID=Z, X=Z)), "tests/data/merge_b.csv" /BY=ID
NEW
END
