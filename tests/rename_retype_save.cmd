-- SAVE rename= retypes float column X to integer Y% on output (truncates
-- toward zero).  Read the file back to confirm the header carries Y% and the
-- values are the truncated integers.
OPTIONS SAVEOVERWRT YES
USE "tests/data/rename_retype.csv"
SAVE "tests/data/rename_retype_out.csv" (RENAME=(X=Y%))
RUN
NEW
USE "tests/data/rename_retype_out.csv"
NAMES
PRINT Y%
RUN
END
