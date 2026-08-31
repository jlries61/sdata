-- ADR-060: LET/SET missing '=' after the variable name must fail cleanly,
-- not silently continue parsing as if the statement were well-formed.
LET X 5
QUIT
