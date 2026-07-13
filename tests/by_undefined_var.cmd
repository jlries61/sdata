-- Issue #50 (companion): BY naming a variable that is not a table column has
-- the identical silent-no-op defect as SORT and must also fail loudly with an
-- undefined-variable error (exit 1) instead of establishing a bogus all-missing
-- group on the misspelled name.
NEW
REPEAT 3
LET N% = 4 - RECNO()
RUN
BY N
RUN
