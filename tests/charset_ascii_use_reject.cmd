-- PD-8 / ADR-0021: USE /CHARSET=ASCII against data containing a non-ASCII
-- byte now fails outright (was: warn and continue, exit 0, dataset loaded).
USE "tests/data/charset_ascii_bad.csv" / CHARSET=ASCII
PRINT NAME$ SCORE
RUN
