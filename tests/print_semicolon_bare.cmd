-- A bare "PRINT ;" (no items, trailing semicolon) prints nothing and no newline, as in
-- BWBASIC, whereas a bare "PRINT" still prints the record's variables. A leading separator
-- before the first item is ignored.
LET X = 5
PRINT ;
PRINT ; 1
RUN
QUIT
