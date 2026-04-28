-- Test BY group processing, BOG() and EOG() functions, and row-wise aggregates
USE "tests/data/sample.csv"
BY CATEGORY$

-- The initial RUN establishes the data and the grouping order.
RUN

-- The second RUN processes the now-grouped data.
LET TOTAL = SUM(VAL1, VAL2, VAL3)
LET IS_FIRST = BOG()
LET IS_LAST = EOG()

PRINT RECNO() CATEGORY$ IS_FIRST IS_LAST TOTAL
RUN
RUN

QUIT
