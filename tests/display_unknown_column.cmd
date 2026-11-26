-- DISPLAY: a varlist naming an unknown column is a clean error (F33);
-- it used to print a column of "." for the typo'd name (ADR-069).
USE "tests/data/sample.csv"
DISPLAY VAL1 BOGUSVAR
QUIT
