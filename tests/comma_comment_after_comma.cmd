-- ADR-080 D3: a "--" comment between the trailing comma and the end of the line
-- still counts as a continuation. Before, the comment cancelled it and the 2
-- on the next line was a syntax error.
PRINT 1, -- first value
2
RUN
QUIT
