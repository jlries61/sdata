-- Issue #54: double precision retained internally and across a SAVE/USE
-- round-trip.  With single-precision Float this value loses accuracy after
-- ~7 significant digits; with IEEE double it is retained.  DIGITS 15 exposes
-- the stored precision (default DIGITS 5 would hide it).
DIGITS 15
NEW
REPEAT 1
LET X = 1.2345678901234
PRINT X
SAVE "tests/dpr_out.csv"
RUN
USE "tests/dpr_out.csv"
PRINT X
RUN
SYSTEM "rm -f tests/dpr_out.csv"
QUIT
