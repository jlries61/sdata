-- NOTE (ADR-059): a permanent variable buried inside a unary operator is
-- also rejected -- Reject_If_Permanent must recurse into Expr_Unary_Op's
-- Operand, not just Expr_Binary_Op's Left/Right.
USE "tests/data/charset_ascii_clean.csv"
NOTE -SCORE
RUN
QUIT
