-- F34 (2026-10-19 stress test) regression: a data row with
-- table:number-rows-repeated > 1000 must be expanded, not treated as
-- trailing padding that ends the read.  Fixture: header; 7; 0 x2000; 9;
-- then LibreOffice-style trailing blank padding (1048576 empty rows),
-- which must still be skipped (expect 2002 records, max 9).
USE "tests/data/ods_repeated_rows.ods"
RUN
STATS
END
