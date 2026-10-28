-- F18/F33 regression: a malformed or oversized numeric operand is a syntax
-- error naming the line, not "CONSTRAINT_ERROR: bad input for 'Value".
USE "tests/data/sample.csv" /NSCAN=-5
QUIT
