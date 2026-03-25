-- Test: a WRITE statement in a later data step must not suppress automatic
-- output in an earlier step.  Regression test for Has_Output_Statement
-- boundary fix.
USE "tests/data/sample.csv"
IF CATEGORY = "A" THEN DELETE
RUN

-- Second step uses WRITE; must not affect first step's output.
USE "tests/data/sample.csv"
IF CATEGORY = "A" THEN WRITE
RUN
QUIT
