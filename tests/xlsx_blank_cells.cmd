-- F37 (2026-10-19 stress test) regression: OOXML omits blank cells, so a
-- cell's column comes from its r="B3" reference, not its ordinal position.
-- Part 1: sdata's own writer omits blank cells; they must round-trip in place.
-- Part 2: an openpyxl-written workbook with blank cells in a character and
-- numeric column.
USE "tests/data/xlsx_blank_roundtrip.csv"
SAVE "tests/data/xlsx_blank_gen.xlsx"
RUN
USE "tests/data/xlsx_blank_gen.xlsx"
DISPLAY
USE "tests/data/xlsx_blank_cells.xlsx"
DISPLAY
SYSTEM "rm -f tests/data/xlsx_blank_gen.xlsx"
END
