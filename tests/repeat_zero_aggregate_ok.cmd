-- issue #66 boundary case (renamed from repeat_zero_sort_ok.cmd, see issue
-- #67): REPEAT 0 is the documented "cancel any active REPEAT" form
-- (SData_Core.Commands.Execute_REPEAT clears Repeat_Active when Count = 0)
-- -- it does not open a data-generation window, so an Immediate command
-- right after it must not be rejected by #66's REPEAT-active guard. This
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
