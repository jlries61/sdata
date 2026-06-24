-- Regression: numeric-looking values in a '$' (character) column must load
-- as strings.  Previously USE aborted with "Expected String for column ..."
-- (reported for adultdata1, whose fnlwgt$ column holds numbers like 77516).
USE "tests/data/numeric_string_col.csv"
PRINT "LABEL=[", LABEL$, "] N=", N
RUN
QUIT
