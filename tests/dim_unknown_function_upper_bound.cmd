-- ADR-062/issue #76: DIM's explicit-upper-bound form (1 TO <expr>) is
-- independently checked too, not just the single-argument form's implicit
-- upper bound (see dim_unknown_function_bound.cmd) -- Check_Statement's
-- Stmt_DIM arm checks both Arr_Start_Expr and Arr_End_Expr.
DIM A(1 TO BOGUSFUNC(5))
QUIT
