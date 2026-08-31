-- PE-4 / ADR-061 (sdata-core ADR-0022): Category B behavior change -- ODF/OOXML
-- import warnings (gated by Put_Line_Error, which has no internal Local_Echo/
-- Quiet_Mode gating of its own) must now print even under -q, matching the
-- man page's documented -q contract ("Error messages are still written to
-- standard error") and closing the pre-existing inconsistency where these
-- warnings were silently swallowed under -q. tests/data/pe4_ooxml_noninteger_warning.xlsx
-- has a "X%" (integer-typed by suffix) column holding 1.5, triggering the
-- "non-integer value truncated" warning on import.
USE "tests/data/pe4_ooxml_noninteger_warning.xlsx"
DISPLAY
QUIT
