-- Verify that a malformed ODS file raises Script_Error (not Program_Error),
-- so -k can catch it and execution continues.
USE "tests/data/bad.ods"
PRINT "continued after error"
RUN
QUIT
