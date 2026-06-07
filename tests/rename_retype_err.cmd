-- USE rename= rejects a numeric->character boundary crossing (all-or-nothing).
USE "tests/data/rename_retype.csv" (RENAME=(X=Y$))
NAMES
END
