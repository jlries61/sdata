-- Per-target format options: one target with HEADER=NO, one with default CSV.
-- Verify the per-target options are honored by reading back the no-header file.
USE "tests/data/merge_a.csv"
SAVE "tests/data/multi_out_p.csv" (HEADER=NO), "tests/data/multi_out_q.csv" (FMT=CSV)
RUN

-- Read back the no-header file: first column should be COL1 (no header row)
USE "tests/data/multi_out_p.csv"
NAMES
NEW

-- Read back the with-header file: columns should be ID and X
USE "tests/data/multi_out_q.csv"
NAMES
NEW
END
