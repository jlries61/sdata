-- Explicit KEEP naming an IN= provenance variable cancels its automatic
-- removal, promoting it to a genuine permanent variable (design.md sec3.5's
-- "Temporary -> Permanent via KEEP") -- it then survives RUN and is written
-- by SAVE like any other column. fromB is not named in KEEP, so it is still
-- auto-dropped and absent from both NAMES and the saved file.
OPTIONS SAVEOVERWRT YES
USE "tests/data/merge_a.csv" (IN=fromA), "tests/data/merge_b.csv" (IN=fromB) /APPEND
SAVE "tests/data/use_merge_in_keep_promotes_out.csv"
KEEP ID fromA
RUN
NAMES
NEW
USE "tests/data/use_merge_in_keep_promotes_out.csv"
NAMES
RUN
END
