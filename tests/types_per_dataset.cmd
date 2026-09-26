-- /TYPES= is legal as a per-dataset paren option as well as a
-- whole-statement slash option, like NSCAN=/SKIP=/MAXROWS= (ADR-084).
USE "tests/data/missing_declared.csv" (TYPES="VALUE")
NAMES
END
