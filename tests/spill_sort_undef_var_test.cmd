-- Regression test for a question raised reviewing sdata-core PR #101
-- (the EAV disk-spill schema, ADR-0011): "how is it possible for a SORT
-- key to not be a real column?"
--
-- Answer: Table.Row_Count and Table.Column_Count are independent
-- counters. The interpreter's undefined-variable guard for SORT (added
-- for issue #50) only fires when Column_Count > 0 at the time SORT
-- executes. Dropping every column (DROP takes effect at the end of the
-- next RUN) drives Column_Count back to 0 while Row_Count stays positive,
-- reopening that bypass -- so a SORT on a name that was never a column at
-- all sails through instead of erroring.
--
-- This specifically exercises the disk-spill path: force a spill (see
-- .flags) while the real columns A/B/C still exist, then DROP all three
-- (taking effect at the end of this RUN), then SORT on a name (ZZZ) that
-- was never a column and never spilled. Under the EAV schema this reaches
-- Sorting.Sort's disk-path rebuild with an unresolvable sort key
-- (Backing_Store.Col_Id returns 0), which must be tolerated the same way
-- the in-memory path already tolerates an unknown key (treated as
-- all-Missing), not crash or corrupt the table.
SYSTEM "printf 'A,B,C\n1,2,3\n4,5,6\n7,8,9\n10,11,12\n' > tests/data/spill_sort_undef_var_src.csv"
USE "tests/data/spill_sort_undef_var_src.csv"
DROP A
DROP B
DROP C
RUN
SORT ZZZ
RUN
SYSTEM "rm -f tests/data/spill_sort_undef_var_src.csv"
QUIT
