-- Systems-designer finding B-1: a column literally named "NA" must survive
-- verbatim when /MISSING="NA" is declared for a DIFFERENT column in the
-- same file.  OOXML's header-name collector (Collect_OOXML_Headers) reuses
-- Get_Cell_Value to read the header row; without Check_Missing defaulting
-- to False there specifically, this header would have been silently
-- replaced with a synthetic "COL1".  ODF's own header reader never calls
-- Get_Cell_Value at all and is unaffected by construction, but is tested
-- here too for symmetry and regression coverage.
USE "tests/data/missing_header_na.csv" / MISSING="NA"
SAVE "tests/data/missing_header_na_gen.ods" / MISSING="NA"
RUN
USE "tests/data/missing_header_na.csv" / MISSING="NA"
SAVE "tests/data/missing_header_na_gen.xlsx" / MISSING="NA"
RUN
USE "tests/data/missing_header_na_gen.ods" / MISSING="NA"
NAMES
RUN
USE "tests/data/missing_header_na_gen.xlsx" / MISSING="NA"
NAMES
RUN
SYSTEM "rm -f tests/data/missing_header_na_gen.ods tests/data/missing_header_na_gen.xlsx"
END
