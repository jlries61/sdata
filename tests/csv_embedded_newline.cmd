-- F02 regression: a quoted field containing a newline (or a doubled quote)
-- is one field of one record, and sdata can read back what SAVE writes.
USE "tests/data/csv_embedded_newline.csv"
SAVE "tests/data/csv_embedded_newline_gen.csv"
RUN
USE "tests/data/csv_embedded_newline_gen.csv"
DISPLAY
SYSTEM "rm -f tests/data/csv_embedded_newline_gen.csv"
END
