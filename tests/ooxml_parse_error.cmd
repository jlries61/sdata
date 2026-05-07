-- Verify that a malformed XLSX file raises Script_Error (not Program_Error),
-- so -k can catch it and execution continues.
USE "tests/data/bad.xlsx"
PRINT "continued after error"
RUN
QUIT
