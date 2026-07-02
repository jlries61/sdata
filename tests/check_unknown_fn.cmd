-- Entry-time check: an unknown function name is rejected before the data step.
-- FOOBAR is not a registered function, so the analyzer must raise pre-RUN and
-- no "RUN complete" line may appear.
USE MOCK
LET X = FOOBAR(SALARY)
RUN
