-- A declared column the file does not have is a hard error, not a silent
-- no-op: a typo that were ignored would leave the column on inference,
-- exactly what /TYPES= exists to prevent (ADR-084; KEEP/DROP precedent).
USE "tests/data/types_demote.csv" / TYPES="NOSUCH"
NAMES
END
