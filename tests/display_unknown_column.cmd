-- DISPLAY: a varlist naming an unknown column must not crash (ADR-069).
-- Get_Column_Type raises for a name that doesn't exist; Has_Column guards
-- every call, defaulting an unknown column to right-justified -- matching
-- the pre-existing silent "." behavior for a typo'd variable name.
USE "tests/data/sample.csv"
DISPLAY VAL1 BOGUSVAR
QUIT
