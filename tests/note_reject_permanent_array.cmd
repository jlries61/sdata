-- NOTE (ADR-059/ADR-063): a whole permanent array is rejected the same as a
-- permanent scalar -- it's still a per-row vector (one array per record),
-- just with multiple elements instead of one. Rejection now names the
-- specific failing element (P(1), the first in Start_Idx..End_Idx), not
-- just the bare array name, matching the per-element check ADR-063 added.
USE "tests/data/charset_ascii_clean.csv"
DIM P(1 TO 2)
RUN
NOTE P
QUIT
