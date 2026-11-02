-- F46: OPTIONS CHARSET / OUTPUT /CHARSET= govern output only; a later USE
-- still auto-detects its input (UTF-8 here) instead of inheriting UTF-16.
OPTIONS CHARSET UTF-16
USE "tests/data/charset_euro.csv"
RUN
QUIT
