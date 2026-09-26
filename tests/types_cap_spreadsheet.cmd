-- ADR-0020's coercion-warning cap applies on the SPREADSHEET path too, not
-- just CSV (ADR-0027 B-2).  Build an .ods whose LABEL column holds 12 text
-- cells, then read it back declaring that column numeric: every cell fails
-- to parse, so exactly 10 warnings appear followed by the suppression
-- summary -- identical wording and cap to the CSV reader.
USE "tests/data/types_manytext.csv"
SAVE "tests/data/types_manytext_gen.ods"
RUN
USE "tests/data/types_manytext_gen.ods" / TYPES="LABEL"
NAMES
SYSTEM "rm -f tests/data/types_manytext_gen.ods"
END
