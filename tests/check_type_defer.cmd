-- Entry-time check: when the RHS kind is indeterminate (Val_Missing), the
-- analyzer must NOT raise -- it defers to runtime.  The dot literal makes
-- SALARY + . return Val_Missing from Static_Result_Kind.  RUN must complete.
USE MOCK
LET FOO = SALARY + .
RUN
