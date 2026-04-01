-- Test SELECT ... END SELECT multi-line block parsing
NEW
USE MOCK
SELECT (ID)
  CASE (1): LET V$ = "One"
  CASE (2): LET V$ = "Two"
  OTHERWISE: LET V$ = "Other"
END SELECT
PRINT ID, V$
RUN
QUIT
