-- F14 (2026-10-19 stress test) regression: VAR/STD must not use the
-- sum-of-squares difference.  X is a constant column (the old formula took
-- Sqrt of a tiny negative and aborted STATS); Y is 1e9 + {0..4} repeated
-- (the old formula lost every significant digit: true VAR = 2.10526).
USE "tests/data/var_stability.csv"
STATS X Y /STATS=N MEAN STD VAR
REPEAT 1
LET A = VAR(1000000000.1, 1000000000.2, 1000000000.3)
PRINT A
RUN
END
