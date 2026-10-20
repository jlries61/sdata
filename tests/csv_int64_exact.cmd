-- F42 regression: values in a % (integer) CSV column are parsed exactly,
-- including ids above 2**53 and the int64 limits.
USE "tests/data/csv_int64.csv"
DISPLAY
SAVE "tests/data/csv_int64_gen.csv"
RUN
SYSTEM "cat tests/data/csv_int64_gen.csv; rm -f tests/data/csv_int64_gen.csv"
END
