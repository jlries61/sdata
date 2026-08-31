-- ADR-060: a parse error inside a function-call argument list (a missing
-- closing paren) must fail the whole script cleanly, not print a warning
-- and silently accept a truncated/malformed expression.
SET X = SQRT(5
QUIT
