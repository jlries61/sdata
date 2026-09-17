-- TABLES /SAVE= and /CHISQFILE= with an UNQUOTED filename must be
-- converted to uppercase, matching USE/SAVE's own documented rule
-- (design.md: "If the file name is unquoted, it is converted to
-- uppercase") -- confirmed missing for TABLES specifically (both
-- /SAVE= and /CHISQFILE= copied the raw token unmodified, regardless of
-- quoting). Uses FPATH /SAVE so the unquoted, extensionless names
-- resolve under tests/data/ rather than the CWD.
FPATH "tests/data" /SAVE
USE "tests/data/freq.csv"
TABLES REGION$*PRODUCT$ /SAVE=tables_save_unquoted_out /CHISQ /CHISQFILE=tables_save_unquoted_chisq
SYSTEM "test -f tests/data/TABLES_SAVE_UNQUOTED_OUT.CSV && echo MAIN_UPPERCASE_EXISTS || echo MAIN_MISSING"
SYSTEM "test -f tests/data/TABLES_SAVE_UNQUOTED_CHISQ.CSV && echo CHISQFILE_UPPERCASE_EXISTS || echo CHISQFILE_MISSING"
FPATH
SYSTEM "rm -f tests/data/TABLES_SAVE_UNQUOTED_OUT.CSV tests/data/TABLES_SAVE_UNQUOTED_CHISQ.CSV"
QUIT
