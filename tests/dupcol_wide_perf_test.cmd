-- sdata-core#156/ADR-0028/ADR-0029 regression: a wide file (20,000 columns)
-- with a column name repeated 3 times must still warn correctly (the same
-- Insert-on-duplicate correctness trap as dupcol_triple_test.cmd, combined
-- here with width) and must complete well inside this suite's 10s per-test
-- timeout. Before the fix, a file this wide took ~49s purely from
-- Warn_If_Duplicate_Name's O(n^2) linear scan (doc/performance_assessment.md
-- Sec4); Add_Column/Add_Output_Column's own unconditional per-insert cursor-
-- cache rebuild (ADR-0029) was an independent, equally quadratic cost found
-- while verifying the first fix -- fixing either alone left this test timing
-- out. The generated fixture (tests/data/dupcol_wide_gen/, gitignored, built
-- by `make check` itself -- see Makefile) is not committed; its shape is
-- documented here and in the Makefile comment.
USE "tests/data/dupcol_wide_gen/dupcol_wide.csv"
RUN
QUIT
