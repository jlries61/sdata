-- Regression test: a dataset with more columns than SQLite's per-table
-- column limit (~2000) should produce a clear actionable error when the
-- spill backend rejects the CREATE TABLE, not a misleading "disk full?" message.
--
-- Strategy: generate a CSV with 2100 columns at runtime via SYSTEM, then
-- USE it with -m 100 (see .flags) so the very first row spills (2100 cells
-- exceeds the 100-cell in-memory budget), triggering the SQLite cap.
--
-- The generated file is gitignored; it is regenerated on every test run.
-- NOTE: BSD/macOS `seq -s` differs from GNU seq (trailing separator, no final
-- newline), which mangled the generated CSV. `seq | paste -sd,` is portable
-- across both: it joins with a comma and appends a trailing newline.
SYSTEM "seq 1 2100 | sed 's/^/c/' | paste -sd, - > tests/data/wide_table.csv && seq 1 2100 | paste -sd, - >> tests/data/wide_table.csv && seq 1 2100 | paste -sd, - >> tests/data/wide_table.csv"
USE "tests/data/wide_table.csv"
RUN
QUIT
