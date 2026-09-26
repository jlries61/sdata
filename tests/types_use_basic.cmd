-- USE /TYPES= pins a column's type, overriding NSCAN inference (ADR-084).
-- Without it, "NA" at row 2 is inside the scan window and makes VALUE
-- character; declaring it float keeps the column numeric and coerces the
-- offending value to missing by the pre-existing path.
USE "tests/data/missing_declared.csv" / TYPES="VALUE"
NAMES
PRINT ID VALUE
RUN
END
