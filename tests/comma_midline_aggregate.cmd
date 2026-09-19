-- ADR-080 D1: comma between AGGREGATE outvar=fn(invar) items
-- A mid-line comma in a comma-free position is a syntax error; a comma may only
-- end a line here. (Before, it was silently skipped.)
AGGREGATE A=SUM(X), B=MEAN(X)
QUIT
