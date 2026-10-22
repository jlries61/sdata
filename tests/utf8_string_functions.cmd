-- F25 (2026-10-19 stress test) regression: string functions work in
-- characters (UTF-8 code points), never splitting a multi-byte character,
-- and case mapping must not corrupt UTF-8.
USE "tests/data/utf8_strings.csv"
LET L$ = LCASE$(NAME$)
LET U$ = UCASE$(NAME$)
LET N = LEN(NAME$)
LET LF$ = LEFT$(NAME$, 2)
LET RT$ = RIGHT$(NAME$, 2)
LET MD$ = MID$(NAME$, 2, 2)
LET P = INSTR(NAME$, "b")
LET IX = INDEX(NAME$, "b")
LET MT = MATCH(NAME$, "b", 1)
SAVE "tests/data/utf8_strings_gen.csv"
RUN
SYSTEM "cat tests/data/utf8_strings_gen.csv; rm -f tests/data/utf8_strings_gen.csv"
END
