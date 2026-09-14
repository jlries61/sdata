-- design.md sec5.4: "Statement ending with comma shall be continued to next
-- line" is unconditional -- even when the preceding statement's own grammar
-- has no comma role at all (LET's assignment isn't a comma-delimited list),
-- the trailing comma is still purely a continuation marker and must not
-- itself become a spurious "Unrecognized command ','" error. The valid next
-- statement (PRINT X) executes normally.
LET X=1,
PRINT X
RUN
QUIT
