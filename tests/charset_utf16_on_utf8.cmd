-- F46: a UTF-8 file read with CHARSET=UTF-16 (e.g. inherited from an
-- OUTPUT ... /CHARSET=UTF-16) is an error, not garbage.
USE "tests/data/charset_euro.csv" /CHARSET=UTF-16
RUN
QUIT
