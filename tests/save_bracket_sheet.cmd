-- Regression test: SAVE "filename[SheetName]" bracket-sheet syntax.
-- Verifies the parser correctly extracts the sheet name from the filename
-- and does not pass the brackets as part of the file path (Task 8 regression).
USE "tests/data/sample.ods"
SAVE "tests/data/save_bracket_out.ods[Results]"
RUN
NEW
END
