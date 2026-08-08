-- Issue #71 / systems-designer Finding 2: REMOVE n[-m]'s line-editor
-- parser used to call Real'Value unconditionally on the token following
-- '-', assuming it was always Token_Numeric_Literal. A .i/.n literal
-- (Token_Infinity/Token_NaN) carries no text, so this used to raise an
-- uncaught Constraint_Error ("Internal error"-shaped) instead of a clean,
-- descriptive error. Confirms both the bare-argument and range-argument
-- positions are guarded, and that the REPL keeps accepting input after
-- the error (same recovery contract as repl_error_recovery.cmd).
LET A = 1
LET A = 2
LET A = 3
REMOVE .i
REMOVE 1-.n
RUN
PRINT A
RUN
QUIT
