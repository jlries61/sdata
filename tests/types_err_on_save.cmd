-- /TYPES= is USE-only, like NSCAN=/SKIP=/MAXROWS=: declaring a column's
-- type is meaningless for an output target, whose types come from the
-- table being written (ADR-084).
USE "tests/data/types_demote.csv"
SAVE "tests/data/types_never.csv" / TYPES="CODE"
END
