-- /TYPES= on an OOXML input, end to end through the interpreter (the unit
-- tests cover the reader directly; this covers the language path).  LABEL
-- holds text; declaring it float reinterprets what it can and coerces the
-- rest to missing, with the same capped warnings as CSV and ODF.
USE "tests/data/types_manytext.csv"
SAVE "tests/data/types_manytext_gen.xlsx"
RUN
USE "tests/data/types_manytext_gen.xlsx" / TYPES="LABEL"
NAMES
SYSTEM "rm -f tests/data/types_manytext_gen.xlsx"
END
