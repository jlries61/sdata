-- F46: UTF-32 (a BOM-writing iconv name) gets one byte-order mark per file
-- (not one per field), and is auto-detected when read back.
USE "tests/data/charset_euro.csv"
SAVE "tests/data/cs_out_u32.csv" /CHARSET=UTF-32
RUN
USE "tests/data/cs_out_u32.csv"
DISPLAY NAME$
RUN
SYSTEM "rm -f tests/data/cs_out_u32.csv"
QUIT
