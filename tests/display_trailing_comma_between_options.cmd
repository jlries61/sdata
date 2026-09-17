-- Skip_Continuation_Comma is called once per iteration of the new
-- slash-option loop, so a trailing comma BETWEEN two options (not just
-- between the printed varlist and the first option) must also parse
-- cleanly (code-review MINOR-1).
USE "tests/data/display_rows.csv"
RUN
DISPLAY /FIRST=2,
    /LAST=2
QUIT
