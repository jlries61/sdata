-- Regression test for sdata-core ADR-0027 / PR #147: Detect_Inf used to
-- return before the type dispatch, so
-- an "Inf" cell in a column declared CHARACTER became numeric infinity in a
-- Col_String column, raised inside Coerce_Value, and was dropped by the
-- generic handler with an uncapped legacy warning -- on both spreadsheet
-- readers, while CSV handled it correctly.  All three must now agree.
USE "tests/data/inf_values.ods" / TYPES="X$"
PRINT X$
RUN
USE "tests/data/inf_values.xlsx" / TYPES="X$"
PRINT X$
RUN
USE "tests/data/inf_values.csv" / TYPES="X$"
PRINT X$
RUN
-- Declared NUMERIC, Inf must still be infinity, not text.
USE "tests/data/inf_values.ods" / TYPES="X"
PRINT X
RUN
END
