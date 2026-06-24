--  Issue #31: a literal whose kind conflicts with the target variable's
--  suffix-derived kind is rejected when the assignment is *entered* (parse
--  time), not deferred to RUN.  ID is an integer column (no '$' suffix), so
--  assigning a string literal to it fails immediately -- the whole script is
--  rejected during parsing, so neither USE nor the PRINT below ever runs and
--  no output precedes the error.
USE "mock"
PRINT "this PRINT never runs (the script fails to parse first)"
LET ID = "StringVal"
RUN
