-- Regression: issue #82. A single-target SAVE (IF=...) previously bypassed
-- the IF= filter entirely when flushed via implicit end-of-record auto-flush
-- (no explicit WRITE), because Execute_Declarative's single-target legacy
-- fast-path delegated straight to Legacy_Execute_SAVE without checking for
-- an IF_Expr option. Only ID=2 (ID>1) should survive into the saved file.
OPTIONS SAVEOVERWRT YES
USE "tests/data/merge_a.csv"
SAVE "tests/data/save_single_target_if_out.csv" (IF=ID>1)
RUN
NEW
USE "tests/data/save_single_target_if_out.csv"
PRINT ID, X
RUN
END
