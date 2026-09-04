-- ADR-062/issue #76: NOTE evaluates an arbitrary expression the same way
-- PRINT does, but never reached PRINT's static Check_Statement/Check_Expr
-- checking before this fix -- an unknown function silently printed a
-- missing-value marker instead of erroring. Now raises the same clean
-- error PRINT already gives for the identical mistake.
SET X = 5
RUN
NOTE BOGUSFUNC(X)
QUIT
