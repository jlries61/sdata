-- Same shape with IF=.
USE "tests/data/display_rows.csv"(KEEP=ID, IF=ID>1)
RUN
DISPLAY
QUIT
