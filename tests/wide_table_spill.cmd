-- Regression test: a dataset with more columns than SQLite's per-table
-- column limit (~2000) used to fail with a "too many columns" error; the
-- EAV disk-spill schema (ADR-0011, jlries61/sdata#64) removes that ceiling
-- entirely. This now verifies the wide dataset spills, reads back, and
-- round-trips correctly across the full column range -- including columns
-- well past the old ~2000-column limit -- not just that RUN succeeds.
--
-- Strategy: generate a CSV with 2100 columns at runtime via SYSTEM, then
-- USE it with -m 100 (see .flags) so the very first row spills (2100 cells
-- exceeds the 100-cell in-memory budget), triggering a multi-segment spill.
-- Every column cK's value equals K in every row, so printing c1/c1050/c2100
-- checks both ends and the middle of the column range round-trip correctly.
--
-- The generated file is gitignored; it is regenerated on every test run.
-- NOTE: BSD/macOS `seq -s` differs from GNU seq (trailing separator, no final
-- newline), which mangled the generated CSV. `seq | paste -sd,` is portable
-- across both: it joins with a comma and appends a trailing newline.
SYSTEM "seq 1 2100 | sed 's/^/c/' | paste -sd, - > tests/data/wide_table.csv && seq 1 2100 | paste -sd, - >> tests/data/wide_table.csv && seq 1 2100 | paste -sd, - >> tests/data/wide_table.csv"
USE "tests/data/wide_table.csv"
PRINT "c1=" C1 "c1050=" C1050 "c2100=" C2100
RUN
QUIT
