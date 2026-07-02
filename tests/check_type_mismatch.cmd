-- Entry-time check: assigning a string column to a numeric variable is a
-- provable type mismatch at analysis time.  The analyzer must raise pre-RUN
-- and no "RUN complete" line may appear.
USE MOCK
LET FOO = NAME$
RUN
