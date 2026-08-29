-- NOTE (ADR-059): a whole permanent array is rejected the same as a
-- permanent scalar -- it's still a per-row vector (one array per record),
-- just with multiple elements instead of one.
USE "tests/data/charset_ascii_clean.csv"
DIM P(1 TO 2)
RUN
NOTE P
QUIT
