-- Demotion: the header says CODE$ (character) and the declaration says
-- float.  The column must be retyped AND lose its "$" suffix, rather than
-- leaving a numeric column still called CODE$ (ADR-084).
USE "tests/data/types_demote.csv" / TYPES="CODE"
NAMES
PRINT CODE VAL
RUN
END
