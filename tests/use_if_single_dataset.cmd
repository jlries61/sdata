-- Single-dataset USE with a per-dataset IF= (ADR-074/sdata#92).
-- Exercises Execute_USE_Single's RENAME/KEEP/DROP snapshot path, which
-- IF= now shares. Only YEARA=2026 rows should survive.
USE "tests/data/use_if_a.csv" (IF=YEARA=2026)
PRINT IDA XA YEARA
RUN
NEW
END
