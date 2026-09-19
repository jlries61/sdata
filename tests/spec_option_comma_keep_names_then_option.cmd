-- A multi-name KEEP= list followed by an option: the comma between names is a name
-- separator, the one before HEADER= is the option separator.
USE "tests/data/display_rows.csv"(KEEP=ID, GROUP$, HEADER=YES)
RUN
DISPLAY
QUIT
