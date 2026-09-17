-- TABLES /SAVE= (unquoted, no /CHISQFILE=) /CHISQ: the default-derived
-- chi-square filename must match the now-uppercased base's case
-- ("_CHISQ", not "_chisq") so the whole derived name reads consistently
-- rather than a mixed-case "NAME_chisq.CSV".
FPATH "tests/data" /SAVE
USE "tests/data/freq.csv"
TABLES REGION$*PRODUCT$ /SAVE=tables_save_unqchisq_out /CHISQ
SYSTEM "test -f tests/data/TABLES_SAVE_UNQCHISQ_OUT_CHISQ.CSV && echo DERIVED_UPPERCASE_EXISTS || echo DERIVED_MISSING"
FPATH
SYSTEM "rm -f tests/data/TABLES_SAVE_UNQCHISQ_OUT.CSV tests/data/TABLES_SAVE_UNQCHISQ_OUT_CHISQ.CSV"
QUIT
