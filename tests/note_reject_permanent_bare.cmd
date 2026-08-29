-- NOTE (ADR-059): a bare reference to a permanent (table-column) variable
-- is rejected -- permanent variables are per-row vectors with no
-- well-defined single value at NOTE's one-shot Immediate dispatch point.
USE "tests/data/charset_ascii_clean.csv"
NOTE SCORE
RUN
QUIT
