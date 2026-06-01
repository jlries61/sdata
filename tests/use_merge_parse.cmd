-- Test: single-dataset USE via rewritten Parse_USE_Stmt (Task 8 back-compat check).
-- A multi-dataset USE a, b /BY=ID would parse correctly but cannot yet execute
-- (Execute_USE multi-path wiring lands in Task 15).
-- This test verifies the single-dataset legacy path is intact.
USE "tests/data/merge_a.csv"
NAMES
RUN
END
