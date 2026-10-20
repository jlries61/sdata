-- F01 (2026-10-19 stress test) regression: CRLF files left the CR in the
-- last header name and value (making a numeric last column character), and
-- bare-CR files were read as one huge line.  Both must load as clean tables.
USE "tests/data/csv_crlf.csv"
NAMES
DISPLAY
USE "tests/data/csv_bare_cr.csv"
DISPLAY
END
