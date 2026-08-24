-- PC-5: SET's existing truncation warning must still fire correctly under
-- the new 256 default, not just under clen_test.cmd's explicit --clen 5.
-- (SET's value never reaches Table.Coerce_Value at all -- it only touches
-- Temp_Symbols -- so this is basic regression coverage for a path that had
-- no meaningful default to test against before this fix.)
SET Y$ = "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
PRINT LEN(Y$)
RUN
QUIT
