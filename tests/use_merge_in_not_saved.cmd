-- IN= creates a "temporary" provenance variable (design.md): usable during
-- the RUN that follows USE, but never written to a deferred SAVE and gone
-- from the table afterward. Read the saved file back to confirm its header
-- carries neither FROMA nor FROMB, and that NAMES no longer lists them as
-- permanent variables once RUN has completed.
OPTIONS SAVEOVERWRT YES
USE "tests/data/merge_a.csv" (IN=fromA), "tests/data/merge_b.csv" (IN=fromB) /APPEND
SAVE "tests/data/use_merge_in_not_saved_out.csv"
PRINT ID fromA fromB
RUN
NAMES
NEW
USE "tests/data/use_merge_in_not_saved_out.csv"
NAMES
RUN
END
