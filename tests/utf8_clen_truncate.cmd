-- F25: --clen truncation (a byte limit) must not leave half of a multi-byte
-- character.  With --clen 5, "日本語" (9 bytes) is cut to "日" (3 bytes),
-- not to 5 bytes ending mid-character.
USE "tests/data/utf8_strings.csv"
LET S$ = NAME$ + NAME$
LET N = LEN(S$)
PRINT NAME$ S$ N
RUN
END
