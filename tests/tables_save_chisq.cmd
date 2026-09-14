-- TABLES /CHISQ + /SAVE (2-way): a second file, default-derived
-- "<base>_chisq.<ext>" name, one row per computed statistic.
USE "tests/data/freq.csv"
TABLES REGION$*PRODUCT$ /CHISQ /SAVE="tests/data/tables_save_cs_out.csv"
SYSTEM "echo === main ==="
SYSTEM "cat tests/data/tables_save_cs_out.csv"
SYSTEM "echo === chisq ==="
SYSTEM "cat tests/data/tables_save_cs_out_chisq.csv"
SYSTEM "rm -f tests/data/tables_save_cs_out.csv tests/data/tables_save_cs_out_chisq.csv"
QUIT
