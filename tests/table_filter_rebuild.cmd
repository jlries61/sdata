-- Verify that a SELECT filter remains correct after KEEP and DROP
-- modify the column set.  A filter broken by column modification would
-- either show wrong records or crash; a diff catches either.

REPEAT 6
LET N = RECNO()
LET X = N * 10
LET TAG$ = "r"
RUN

-- Filter: only N <= 3 (records 1, 2, 3 visible)
SELECT N <= 3
PRINT N X
RUN

-- DROP TAG$ — filter expression references N which still exists; must hold
DROP TAG$
PRINT N X
RUN

-- KEEP only N — filter expression references N; must still hold
KEEP N
PRINT N
RUN

QUIT
