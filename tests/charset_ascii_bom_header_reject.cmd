-- PD-8 / ADR-0021 Consequences note (code-review round 2, MINOR-1): a UTF-8
-- BOM in the header row is non-ASCII bytes, so it now correctly hard-fails
-- under CHARSET=ASCII rather than being silently stripped -- pinned here so
-- a future change doesn't "fix" this by moving the header charset check
-- after BOM-stripping under the mistaken assumption it's a regression.
USE "tests/data/charset_ascii_bom_header.csv" / CHARSET=ASCII
PRINT SCORE
RUN
