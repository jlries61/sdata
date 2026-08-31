-- ADR-060: a RENAME= pair list missing the new name after '=' must fail
-- cleanly, not silently accept a malformed rename pair.
USE "tests/data/charset_ascii_clean.csv" (RENAME=(NAME$=))
QUIT
