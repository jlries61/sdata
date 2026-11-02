-- F46 regression: invalid input fails with an error naming the file and the
-- character set; AUTO stays lenient.  Run with -k.
USE "tests/data/charset_bad_utf8.csv" /CHARSET=UTF-8
USE "tests/data/charset_latin1.csv" /CHARSET=UTF-16
USE "tests/data/charset_euro.csv" /CHARSET=NO-SUCH-CHARSET
USE "tests/data/charset_bad_utf8.csv"
