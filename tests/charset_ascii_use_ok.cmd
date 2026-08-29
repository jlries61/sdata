-- PD-8 / ADR-0021: USE /CHARSET=ASCII against clean ASCII data still succeeds.
USE "tests/data/charset_ascii_clean.csv" / CHARSET=ASCII
PRINT NAME$ SCORE
RUN
