-- Entry-time check: within-numeric-family assignments (numeric<->integer) must
-- NOT be rejected.  Coerce_For_Scalar handles these freely at runtime.
-- N% = SALARY: integer target <- numeric column (truncate at runtime, not error)
-- F  = ID:     numeric target <- integer column (promote at runtime, not error)
USE MOCK
LET N% = SALARY
LET F = ID
RUN
