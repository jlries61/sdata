-- F46 (2026-10-19 stress test) regression: any character set the system's
-- iconv knows can be read and written; text is converted to and from UTF-8.
USE "tests/data/charset_latin1.csv" /CHARSET=LATIN1
DISPLAY NAME$
SAVE "tests/data/cs_out_u8.csv" /CHARSET=UTF-8
RUN
SYSTEM "od -An -c tests/data/cs_out_u8.csv | head -2"
-- Unquoted, hyphenated names parse.
USE "tests/data/charset_latin1.csv" /CHARSET=ISO-8859-1
SAVE "tests/data/cs_out_w.csv" /CHARSET=WINDOWS-1252
RUN
SYSTEM "od -An -tx1 tests/data/cs_out_w.csv | head -2"
-- A character the target lacks is representable in CP1252 (the euro sign).
USE "tests/data/charset_euro.csv"
SAVE "tests/data/cs_out_euro.csv" /CHARSET=CP1252
RUN
SYSTEM "od -An -tx1 tests/data/cs_out_euro.csv | tail -2"
-- Round trip through a converted file.
USE "tests/data/cs_out_euro.csv" /CHARSET=CP1252
DISPLAY NAME$
OUTPUT "tests/data/cs_out_txt.txt" /CHARSET=LATIN1
PRINT "café"
RUN
OUTPUT
SYSTEM "od -An -c tests/data/cs_out_txt.txt | head -1"
SYSTEM "rm -f tests/data/cs_out_*"
QUIT
