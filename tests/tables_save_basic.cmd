-- TABLES /SAVE writes the crosstab to an external dataset (ADR-071).
USE "tests/data/freq.csv"
TABLES REGION$*PRODUCT$ /SAVE="tests/data/tables_save_basic_out.csv"
SYSTEM "cat tests/data/tables_save_basic_out.csv"
SYSTEM "rm -f tests/data/tables_save_basic_out.csv"
QUIT
