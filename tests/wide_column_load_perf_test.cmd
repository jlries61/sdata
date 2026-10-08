-- General wide-column-count performance regression guard -- NOT tied to
-- any specific bug. 20,000 all-UNIQUE column names (no duplicates, so this
-- is independent of Warn_If_Duplicate_Name/ADR-0028's fix, which has its
-- own dedicated test in dupcol_wide_perf_test.cmd) exercises only the
-- general per-column load + per-record output-flush path: Add_Column and
-- Add_Output_Column (ADR-0029), and anything added to that path in the
-- future. Must complete well inside this suite's 10s per-test timeout --
-- both halves of that path were independently O(n^2) before ADR-0029
-- (sdata-core#156); a future regression anywhere in it fails this test by
-- timing out, not just running slow. See doc/performance_assessment.md
-- §4 for the real-file measurements this margin is sized against.
USE "tests/data/wide_column_load_gen/wide_column_load.csv"
RUN
QUIT
