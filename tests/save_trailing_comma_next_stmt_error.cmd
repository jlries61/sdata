-- sdata#90 BLOCKER-1: the identical defect in SAVE's own filename parser
-- (Parse_Filename_Into_Save) -- a trailing comma before an unrelated next
-- statement must raise a clear error, not silently swallow it (previously:
-- SAVE "out.csv",\nNAMES\n silently dropped NAMES with no error).
USE "tests/data/freq.csv"
SAVE "tests/data/out.csv",
NAMES
QUIT
