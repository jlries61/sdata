-- /FIRST=<n> rejects a negative value at parse time with a clear message
-- (mirrors TABLES's own /DECIMALS= precedent).
USE "tests/data/display_rows.csv"
RUN
DISPLAY /FIRST=-1
QUIT
