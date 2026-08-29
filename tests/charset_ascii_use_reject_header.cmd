-- PD-8 / ADR-0021, code-review round 1 MAJOR-1: a non-ASCII byte confined
-- to the header (column-name) row must also reject under CHARSET=ASCII,
-- not just a data row -- the header read is a distinct call site from the
-- Skip_Rows/NSCAN loops and previously never routed through Validate_ASCII
-- at all (unwarned before this fix, un-failed after it, until this round's
-- correction).
USE "tests/data/charset_ascii_bad_header.csv" / CHARSET=ASCII
PRINT SCORE
RUN
