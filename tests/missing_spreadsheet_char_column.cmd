-- NUMERIC COLUMNS ONLY (sdata-core ADR-0026, "Numeric columns only") applies
-- identically once /MISSING= reaches ODF/OOXML: NAME$ is explicitly
-- character, and "NA" is a legitimate value there (Nebraska's postal code).
-- Declaring "NA" for some other, numeric column's sake must not discard it
-- on a spreadsheet input any more than it does on CSV.
USE "tests/data/missing_string_col.csv"
SAVE "tests/data/missing_string_col_gen.ods", "tests/data/missing_string_col_gen.xlsx"
RUN
USE "tests/data/missing_string_col_gen.ods" / MISSING="NA"
PRINT NAME$ VAL
RUN
USE "tests/data/missing_string_col_gen.xlsx" / MISSING="NA"
PRINT NAME$ VAL
RUN
SYSTEM "rm -f tests/data/missing_string_col_gen.ods tests/data/missing_string_col_gen.xlsx"
END
