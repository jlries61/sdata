-- /MISSING= and /TYPES= share the same Get_Cell_Value dispatch point on
-- ODF/OOXML, exactly as they already do on CSV (TYPES-11/12): a column
-- declared numeric via /TYPES= honors /MISSING= identically to an inferred
-- numeric column, and a column declared character via /TYPES= does NOT
-- have its values matched against the missing-token set (Target_Type =
-- Col_String returns before Check_Missing is ever consulted).
-- Both A and B come back from the CSV as character ($-suffixed) after the
-- first plain USE, since neither column is numeric-only; the generated
-- spreadsheet's cells are literal "NA"/"5"/"X" text regardless.  Re-reading
-- with /TYPES="A,B$" forces A back to numeric (demoting the name) while B$
-- stays character.
USE "tests/data/missing_types_compose.csv"
SAVE "tests/data/missing_types_compose_gen.xlsx"
RUN
USE "tests/data/missing_types_compose_gen.xlsx" / TYPES="A,B$" / MISSING="NA"
NAMES
PRINT A B$
RUN
SYSTEM "rm -f tests/data/missing_types_compose_gen.xlsx"
END
