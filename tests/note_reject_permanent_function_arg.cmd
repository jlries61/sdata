-- NOTE (ADR-059): a permanent variable buried inside a function-call
-- argument is also rejected -- Reject_If_Permanent must recurse into
-- Expr_Function_Call's Arguments, not just check the function name itself.
USE "tests/data/charset_ascii_clean.csv"
NOTE SQRT(SCORE)
RUN
QUIT
