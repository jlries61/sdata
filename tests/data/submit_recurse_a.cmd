-- Indirectly submits B, which submits back to A (cycle)
PRINT "In A"
SUBMIT "tests/data/submit_recurse_b.cmd"
