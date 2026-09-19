-- A continuation comma right after TABLES, before the first request, is skipped
-- (Parse_TABLES calls Skip_Continuation_Comma before every "is there a request?" check).
USE "tests/data/display_rows.csv"
RUN
TABLES,
  GROUP$
QUIT
