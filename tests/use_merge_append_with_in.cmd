-- APPEND with IN= provenance indicators.
-- Each output row originates from exactly one input, so exactly one of
-- fromA/fromB is 1 per row.
USE "tests/data/merge_a.csv" (IN=fromA), "tests/data/merge_b.csv" (IN=fromB) /APPEND
PRINT ID fromA fromB
RUN
NEW
END
