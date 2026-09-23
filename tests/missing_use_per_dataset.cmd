-- USE /MISSING= is also legal as a per-dataset paren option (like NSCAN=,
-- SKIP=, MAXROWS=), not statement-level only.
USE "tests/data/missing_declared.csv" (MISSING="NA")
PRINT ID VALUE
RUN
END
