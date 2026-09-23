-- USE /MISSING=: a declared token is missing regardless of NSCAN position,
-- and does not force the column to character (sdata ADR-083).
USE "tests/data/missing_declared.csv" / MISSING="NA"
PRINT ID VALUE
RUN
END
