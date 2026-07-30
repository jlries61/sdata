-- Regression test for a question raised reviewing sdata-core PR #101
-- (the EAV disk-spill schema, ADR-0011): "how is it possible for a SORT
-- key to not be a real column?"
--
-- Answer: Table.Row_Count and Table.Column_Count are independent
-- counters. The interpreter's undefined-variable guard for SORT (added
-- for issue #50) used to only fire when Column_Count > 0 at the time SORT
-- executes. Dropping every column (DROP takes effect at the end of the
-- next RUN) drove Column_Count back to 0 while Row_Count stayed positive,
-- reopening that bypass -- so a SORT on a name that was never a column at
-- all sailed through instead of erroring. Fixed by issue #67: the guard
-- is now unconditional, so this now errors before ever reaching
-- sdata-core's Sorting.Sort -- the disk-spill unresolvable-key tolerance
-- (Backing_Store.Col_Id returning 0) that motivated this test's original
-- write-up is no longer reachable via this trigger; sdata's own
-- pre-validation catches the undefined name first. This still forces a
-- spill and still proves Column_Count = 0 via DROP does not reopen a
-- bypass -- it just asserts the corrected outcome.
SYSTEM "printf 'A,B,C\n1,2,3\n4,5,6\n7,8,9\n10,11,12\n' > tests/data/spill_sort_undef_var_src.csv"
USE "tests/data/spill_sort_undef_var_src.csv"
SYSTEM "rm -f tests/data/spill_sort_undef_var_src.csv"
DROP A
DROP B
DROP C
RUN
SORT ZZZ
RUN
QUIT
