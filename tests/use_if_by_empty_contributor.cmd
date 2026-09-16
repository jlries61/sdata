-- /BY= match-merge where one spec's IF= drops every row of that input
-- (ADR-074/sdata#92 -- systems-designer 02-systems-designer.md Sec7).
-- merge_a_13.csv: no row has X=999, so this spec contributes 0 rows;
-- the match-merge degenerates to merge_b_23's own two BY groups (ID=2,3),
-- each shown with X missing -- the full-outer-match behavior for an
-- unmatched BY group, same as if A were naturally empty.
USE "tests/data/merge_a_13.csv" (IF=X=999), "tests/data/merge_b_23.csv" /BY=ID
PRINT ID X Y
RUN
NEW
END
