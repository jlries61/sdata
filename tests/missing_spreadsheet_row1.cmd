-- The direct spreadsheet analogue of ADR-0026's "a declared token never
-- forces the column to character" rule, which CSV gets from its NSCAN-window
-- loop.  ODF/OOXML have no scan window -- only a single row-1 type probe --
-- but a declared-missing value landing on THAT row must not force the
-- column to character either.  Row 1's VALUE is genuinely missing in the
-- source CSV; writing it back out with /MISSING="NA" turns that missing
-- cell into literal "NA" text, so the generated spreadsheet's row 1 is a
-- text cell in an otherwise-numeric column -- exactly the case that would
-- have tripped the row-1 probe before Get_Cell_Value's Check_Missing fix.
-- This also exercises the double-count guard: row 1 is visited once by the
-- schema probe and again by the real load, so the summary must read 1
-- match, not 2.
USE "tests/data/missing_row1.csv"
SAVE "tests/data/missing_row1_gen.ods" / MISSING="NA"
RUN
USE "tests/data/missing_row1.csv"
SAVE "tests/data/missing_row1_gen.xlsx" / MISSING="NA"
RUN
USE "tests/data/missing_row1_gen.ods" / MISSING="NA"
NAMES
PRINT ID VALUE
RUN
USE "tests/data/missing_row1_gen.xlsx" / MISSING="NA"
NAMES
PRINT ID VALUE
RUN
SYSTEM "rm -f tests/data/missing_row1_gen.ods tests/data/missing_row1_gen.xlsx"
END
