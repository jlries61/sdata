-- ADR-062/issue #76 regression: Check_Expr is called with
-- Check_Undefined => False for SAVE's IF= option, so an undefined
-- *variable* referenced there is NOT rejected at registration time --
-- it may legitimately be defined by a later statement before the first
-- record is written (see save_if_forward_reference.cmd for the positive
-- case). This test only confirms registration itself doesn't error;
-- it deliberately doesn't assert on filtered row content (see issue #82,
-- an unrelated pre-existing single-target IF= filtering gap).
OPTIONS SAVEOVERWRT YES
USE "tests/data/merge_a.csv"
SAVE "tests/data/save_if_undef_var_out.csv" (IF=NEVERDEFINED=1)
RUN
QUIT
