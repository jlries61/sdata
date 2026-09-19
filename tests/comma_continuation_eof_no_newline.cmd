-- ADR-080: a comma, comment, then end of input with NO final newline still ends the line.
USE "tests/data/display_rows.csv"
RUN
DISPLAY /FIRST=1, -- last line, no newline