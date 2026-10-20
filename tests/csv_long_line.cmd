-- F24 regression: a CSV line longer than 1 MiB (the header here is ~1.3 MB:
-- 90000 columns) is one record, not several.  Expect 2 records and 90000
-- variables.
SYSTEM "awk -f tests/data/gen_long_line.awk > tests/data/csv_long_line_gen.csv"
USE "tests/data/csv_long_line_gen.csv"
RUN
SYSTEM "rm -f tests/data/csv_long_line_gen.csv"
END
