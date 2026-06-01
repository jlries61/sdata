-- Parse test: SAVE with multiple comma-separated targets.
-- Verifies multi-target SAVE syntax parses without error.
-- The SAVE is deferred (not executed) — NEW clears state before RUN.
USE "tests/data/merge_a.csv"
SAVE "tests/data/out_p.csv", "tests/data/out_q.csv"
NAMES
NEW
END
