-- ADR-060: a HEADER= value that isn't YES or NO must fail cleanly rather
-- than silently leaving Header_Val at its unrelated default.
USE "tests/data/charset_ascii_clean.csv" (HEADER=MAYBE)
QUIT
