-- ADR-060: a SELECT/CASE parenthesised condition list missing its closing
-- paren must fail cleanly.
SELECT X
CASE (1,2
END SELECT
QUIT
