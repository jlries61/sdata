-- PD-8 / ADR-0021: SAVE /CHARSET=ASCII against clean ASCII data still
-- succeeds and writes the file unchanged.
USE "tests/data/charset_ascii_clean.csv"
SAVE "tests/data/charset_ascii_save_out.csv" / CHARSET=ASCII
RUN
SYSTEM "cat tests/data/charset_ascii_save_out.csv"
SYSTEM "rm -f tests/data/charset_ascii_save_out.csv"
QUIT
