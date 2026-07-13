-- Issue #50: SORT naming a variable that is not a table column must fail
-- loudly (undefined-variable error, exit 1) rather than silently leaving the
-- data unsorted.  Common trigger: dropping the type suffix (column is N%,
-- script says SORT N).
NEW
REPEAT 3
LET N% = 4 - RECNO()
RUN
SORT N
RUN
