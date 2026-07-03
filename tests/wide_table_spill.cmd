-- Regression test: a dataset with more columns than SQLite's per-table
-- column limit (~2000) should produce a clear actionable error when the
-- spill backend rejects the CREATE TABLE, not a misleading "disk full?" message.
--
-- Strategy: generate a CSV with 2100 columns at runtime via SYSTEM, then
-- USE it with -m 100 (see .flags) so the very first row spills (2100 cells
-- exceeds the 100-cell in-memory budget), triggering the SQLite cap.
--
-- The generated file is gitignored; it is regenerated on every test run.
SYSTEM "seq -s, 1 2100 | sed 's/[0-9][0-9]*/c&/g' > tests/data/wide_table.csv && seq -s, 1 2100 >> tests/data/wide_table.csv && seq -s, 1 2100 >> tests/data/wide_table.csv"
USE "tests/data/wide_table.csv"
RUN
QUIT
