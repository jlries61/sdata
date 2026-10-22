-- issue #66 boundary case (renamed from repeat_zero_sort_ok.cmd, see issue
-- #67): REPEAT 0 requests zero records (F28, 2026-10-19 stress test; it was
-- formerly the "cancel any active REPEAT" form) -- it opens an empty data
-- generation window, and an Immediate command right after it must not be
-- rejected by #66's REPEAT-active guard; the implicit RUN processes 0
-- records. This
-- used to use SORT X, but issue #67 made SORT's undefined-variable guard
-- unconditional -- since REPEAT (any count, including 0) unconditionally
-- clears the table, there is no name SORT could reference here that
-- would still exist, so SORT could no longer isolate the #66 boundary
-- from the #67 guard. AGGREGATE N=N() takes no input-column argument, so
-- it cleanly exercises only the #66 boundary.
NEW
REPEAT 0
AGGREGATE N=N()
QUIT
