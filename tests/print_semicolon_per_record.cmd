-- A trailing semicolon joins each record's output; the unfinished line is closed before
-- the "RUN complete" message so it does not run on.
USE "tests/data/display_rows.csv"
RUN
PRINT GROUP$;
RUN
QUIT
