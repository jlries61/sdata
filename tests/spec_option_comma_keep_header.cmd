-- Round-2 gate fix (MAJOR-1): inside a USE spec option list "( opt, opt )", a comma after a
-- KEEP= list separates OPTIONS, so a keyword option (HEADER=, IF=, ...) may follow it. ADR-080 D1 had
-- made Parse_Variable_List reject any mid-line comma not followed by a name, which broke this.
USE "tests/data/display_rows.csv"(KEEP=ID, HEADER=YES)
RUN
DISPLAY
QUIT
