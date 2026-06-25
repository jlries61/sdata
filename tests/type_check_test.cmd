USE "mock"

--  Deferred (run-time) type mismatch via a NON-literal right-hand side.
--  Assigning the string column NAME$ to the numeric column SALARY is a type
--  error, but because the right-hand side is a variable (not a literal) its
--  kind is only known at RUN.  The parse-time literal check (issue #31) does
--  not and should not fire here; this remains a deferred, run-time error.
PRINT "SALARY BEFORE:"
PRINT SALARY
LET SALARY = NAME$
RUN
