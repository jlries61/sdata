-- PC-5: USE-loaded data exceeding the effective --clen limit (default 256
-- here, no flag given) must warn, matching design.md's general truncation
-- rule -- previously silent (Table.Coerce_Value truncated with no warning
-- at all, unlike LET/SET's already-correct path).
USE "tests/data/clen_load_long_field.csv"
PRINT LEN(NOTES$)
RUN
QUIT
