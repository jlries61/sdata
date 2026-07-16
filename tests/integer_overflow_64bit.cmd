-- Overflow at the new 64-bit boundary must fail cleanly, not wrap.
NEW
REPEAT 1
LET N% = 9223372036854775807
LET N% = N% + 1
PRINT N%
RUN
QUIT
