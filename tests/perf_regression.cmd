-- Performance regression guard (standards review remediation #10).
--
-- Exercises the three data-step paths that were O(n^2) before v0.9.7 on a
-- non-trivial row count:
--   1. per-record output flush  (Get_Column_Type whole-column copy)
--   2. transient /APPEND build   (Add_Row/Set_Value copy-per-cell)
--   3. BY re-sort                (BY dispatched per record)
--
-- With the linear implementations this finishes in ~1-2s.  If any path
-- regresses to O(n^2), 20k/40k rows take minutes and this test blows the
-- harness 10s per-test timeout (TIMEOUT in the Makefile) -> the suite fails.
-- The point is the time bound; the printed count is just a correctness anchor.
OPTIONS SAVEOVERWRT YES

-- Generate 20k rows and write them out (exercises path #1).
REPEAT 20000
LET X = RECNO
LET GRP$ = IF(MOD(RECNO, 2) = 1, "A", "B")
SAVE "tests/data/perf_regression_a.csv"
RUN
NEW

-- Vertically stack two copies -> 40k rows (exercises path #2, then #1).
USE "tests/data/perf_regression_a.csv", "tests/data/perf_regression_a.csv" /APPEND
SAVE "tests/data/perf_regression_b.csv"
RUN
NEW

-- Group the 40k rows and count (exercises path #3, then #1).
USE "tests/data/perf_regression_b.csv"
BY GRP$
IF BOF THEN SET na = 0
IF GRP$ = "A" THEN SET na = na + 1
RUN
REPEAT 1
PRINT "A rows=", na
RUN
END
