-- ADR-062/issue #76: arity checking, not just unknown-function-name
-- checking, reaches NOTE via the same Check_Statement/Check_Expr reuse.
-- MID$ expects 2 or 3 arguments; 1 is an arity error, not a silent
-- missing-value substitution.
NOTE MID$("hi")
QUIT
