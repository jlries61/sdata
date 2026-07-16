-- Issue #54: integers beyond the old 32-bit range must round-trip once Int is
-- 64-bit.  5,000,000,000 exceeds 2^31-1 (~2.1e9); pre-flip it overflows.
NEW
REPEAT 1
LET N% = 5000000000
PRINT N%
SAVE "tests/lir_out.csv"
RUN
USE "tests/lir_out.csv"
PRINT N%
RUN
SYSTEM "rm -f tests/lir_out.csv"
QUIT
