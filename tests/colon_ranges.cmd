-- F36 (2026-10-19 stress test) regression: colon ranges (X1:X3) name every
-- variable in the range, not just X1, in function arguments, STATS,
-- TRANSPOSE, SORT and BY (including the dash form G1-G2).
USE "tests/data/colon_ranges.csv"
LET S = SUM(X1:X3)
LET M = MEAN(X1:X3)
LET C = N(X2:X4)
KEEP S, M, C
RUN
DISPLAY

USE "tests/data/colon_ranges.csv"
STATS X1:X2 /NOPRINT
DISPLAY

USE "tests/data/colon_ranges.csv"
BY G1:G2
AGGREGATE CNT = N()
DISPLAY

USE "tests/data/colon_ranges.csv"
BY G1-G2
AGGREGATE CNT = N()
DISPLAY

USE "tests/data/colon_ranges.csv"
TRANSPOSE /KEEP=X1:X2
DISPLAY

USE "tests/data/colon_ranges.csv"
LET Z = SUM(X1:G2)
RUN
QUIT
