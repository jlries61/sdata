-- Entry-time check: a known function called with the wrong argument count is
-- rejected before the data step.  SQRT takes exactly one argument.
USE MOCK
LET X = SQRT(SALARY, 2)
RUN
