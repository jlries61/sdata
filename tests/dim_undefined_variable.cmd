-- ADR-062/issue #76 regression: Check_Statement is called with
-- Check_Undefined => False for DIM, so an undefined *variable* (as
-- opposed to an undefined *function*) in an array-bound expression is
-- NOT newly rejected by the new checking -- Eval_Bound's own pre-existing
-- "Upper bound is missing" handling applies unchanged.
DIM A(UNDEFINEDVAR)
QUIT
