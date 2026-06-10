-- sdata-core issue #24: a derived (non-table) column that is missing on its
-- first record and character later must upgrade the OUTPUT column type to
-- string, instead of locking to Numeric (from the leading missing) and raising
-- "Expected Numeric for column".  A deliberately-numeric column is unaffected.
USE "mock"
LET DC$ = IF(RECNO = 1, ., "hello")
PRINT DC$
RUN
