-- ADR-080 D1: comma between TRANSPOSE options
-- A mid-line comma in a comma-free position is a syntax error; a comma may only
-- end a line here. (Before, it was silently skipped.)
TRANSPOSE /DROP=A, /DROP=B
QUIT
