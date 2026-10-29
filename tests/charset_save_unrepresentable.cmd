-- F46 regression: a character the output character set cannot represent
-- fails the SAVE and leaves no half-written file behind.
USE "tests/data/charset_euro.csv"
SAVE "tests/data/cs_err_never.csv" /CHARSET=ISO-8859-1
RUN
