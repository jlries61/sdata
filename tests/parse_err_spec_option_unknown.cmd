-- ADR-060: an unrecognized per-dataset spec option must fail cleanly.
USE "tests/data/charset_ascii_clean.csv" (BOGUSOPT=1)
QUIT
