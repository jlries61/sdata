-- Issue #56: SET on an existing loaded/permanent column must fail loudly
-- (hard error, exit 1) instead of silently demoting it to a temporary
-- variable and dropping it from the table.
USE MOCK
SET SALARY = SALARY * 2
RUN
