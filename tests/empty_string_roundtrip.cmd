-- Issue #55: a blank character cell round-trips through SAVE/USE as missing.
NEW
REPEAT 2
LET NAME$ = IF(RECNO() = 1, "Alice", "")
LET N% = NMISS(NAME$)
PRINT NAME$ N%
SAVE "tests/data/empty_rt.csv"
RUN
USE "tests/data/empty_rt.csv"
DISPLAY
QUIT
