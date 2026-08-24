-- PD-3/ADR-0017 regression: an .xlsx whose xl/_rels/workbook.xml.rels uses
-- the OPC-legal ABSOLUTE Target form ("/xl/worksheets/sheet1.xml", the form
-- openpyxl writes) must load correctly, not be rejected with a doubled
-- "xl//xl/..." zip-entry path. Asserts real cell data loaded, not just
-- absence of the "Failed to parse OOXML file" error.
USE "tests/data/xlsx_absolute_target.xlsx"
PRINT NAME$ SCORE
RUN
END
