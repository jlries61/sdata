-- ADR-060: SAVE ... AS with no identifier following must fail cleanly.
-- Parse_SAVE_Stmt's own AS-alias check, distinct from Parse_USE_Stmt's
-- identical-shaped one (both converted, both tested independently).
USE "tests/data/charset_ascii_clean.csv"
SAVE "a.csv" AS 5
RUN
QUIT
