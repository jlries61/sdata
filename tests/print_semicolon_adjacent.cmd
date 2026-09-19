-- ADR-081 (Bywater BASIC 3.20): a semicolon between PRINT items means "immediate
-- sequential output" -- the items are adjacent, with nothing between them. A comma or
-- whitespace still prints one space (sdata does not tab to print zones), and a trailing
-- semicolon suppresses the newline, so PRINT 3; then PRINT 4 share one line.
PRINT "a"; "b"; "c"
PRINT 1; 2
PRINT "x"; 1, 2
PRINT "a", "b"
PRINT "a" "b"
PRINT 3;
PRINT 4
RUN
QUIT
