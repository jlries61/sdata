-- ADR-060: a parse error in a parenthesised grouping expression (missing
-- closing paren) must fail cleanly, not silently accept the inner
-- expression as if the paren mismatch never happened.
SET X = (5 + 3
QUIT
