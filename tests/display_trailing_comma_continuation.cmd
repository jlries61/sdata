-- DISPLAY's new slash-option loop calls Skip_Continuation_Comma before
-- checking for '/', matching Parse_STATS's own precedent -- a trailing
-- comma after the printed varlist, continuing onto /FIRST= on the next
-- line, must parse cleanly.
USE "tests/data/display_rows.csv"
RUN
DISPLAY ID,
    /FIRST=2
QUIT
