-- /MISSING= applies to numeric columns only (ADR-083, code review round 1
-- MAJOR-1).  NAME$ is explicitly character, and "NA" is a legitimate value
-- there (Nebraska's postal code) -- declaring it for some other, numeric
-- column's sake must not discard it.  VAL stays numeric and is unaffected.
USE "tests/data/missing_string_col.csv" / MISSING="NA"
PRINT NAME$ VAL
RUN
END
