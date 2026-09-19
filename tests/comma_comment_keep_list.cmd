-- ADR-080 D3 in a comma-delimited grammar: a comment after the separating comma
-- still continues the KEEP list (the comma stays a real separator, ADR-072).
USE "tests/data/display_rows.csv"
KEEP ID, -- the key
  SCORE
RUN
DISPLAY
QUIT
