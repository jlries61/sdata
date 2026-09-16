-- PCTL used as an ordinary expression function with the wrong number of
-- arguments is caught by the existing Check_Expr/Function_Arity machinery
-- (ADR-075/sdata#93 -- Register_Arity("PCTL", 2, 2)), the same static check
-- every other registered function already gets.
NEW
REPEAT 1
LET X = 5
PRINT PCTL(X)
RUN
QUIT
