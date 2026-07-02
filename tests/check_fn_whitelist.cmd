-- Guard: the analyzer must NOT flag IF(...) (dispatched specially, not in the
-- Dispatch_Table) nor array-element access X(1) (parsed as a function call in
-- batch because DIM has not run yet).  Both must reach a normal RUN.
USE MOCK
DIM X(3)
LET X(1) = 10
LET Y = X(1)
LET Z = IF(SALARY > 55000, 1, 0)
RUN
