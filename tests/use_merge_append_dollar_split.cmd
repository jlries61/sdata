-- APPEND keeps a numeric field and its character counterpart separate.
-- append_num.csv: ID,VAL (numeric).  append_str.csv: ID,VAL$ (character,
-- forced by the trailing "$" in the header).  Because the readers name the
-- character column "VAL$" and the numeric one "VAL", they already carry
-- distinct names, so APPEND yields both VAL (numeric) and VAL$ (character).
USE "tests/data/append_num.csv", "tests/data/append_str.csv" /APPEND
PRINT ID VAL VAL$
RUN
NEW
END
