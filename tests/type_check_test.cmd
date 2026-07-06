USE "mock"

--  Entry-time (pre-RUN) type mismatch via a NON-literal right-hand side.
--  Assigning the string column NAME$ to the numeric column SALARY is a type
--  error caught by the analyzer before any record is processed.  The RHS is a
--  variable (not a literal), so the issue #31 literal check does not apply;
--  this test complements that check by covering the variable-RHS case on an
--  existing table column.  The analyzer rejects the statement at entry time,
--  so the deferred PRINT statements never execute.
PRINT "SALARY BEFORE:"
PRINT SALARY
LET SALARY = NAME$
RUN
