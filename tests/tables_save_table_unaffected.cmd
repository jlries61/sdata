-- TABLES /SAVE never touches the internal table (ADR-049's no-mutation
-- guarantee, preserved by ADR-071's Table_View design): the active SELECT
-- filter and the real Data Table are unchanged after TABLES ... /SAVE=....
USE "tests/data/freq.csv"
SELECT REGION$="East"
TABLES PRODUCT$ /SAVE="tests/data/tables_save_unaff_out.csv"
DISPLAY
SYSTEM "rm -f tests/data/tables_save_unaff_out.csv"
QUIT
