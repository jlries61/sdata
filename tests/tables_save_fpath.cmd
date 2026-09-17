-- TABLES /SAVE and the /CHISQ file (both default-derived and /CHISQFILE=)
-- resolve a relative (unqualified) filename against the active FPATH /SAVE
-- directory, exactly like the SAVE command's own filename (design.md's
-- TABLES entry: "the filename is resolved the same way as the SAVE
-- command's filename, relative to the active FPATH") -- both go through
-- Full_Path's "SAVE" category (src/sdata-interpreter-execute_tables.adb),
-- so /CHISQFILE= inherits it too, not just the plain /SAVE= filename.
FPATH "tests/data" /SAVE
USE "tests/data/freq.csv"
TABLES REGION$*PRODUCT$ /CHISQ /SAVE="tables_save_fpath_out.csv"
SYSTEM "echo === main file ==="
SYSTEM "cat tests/data/tables_save_fpath_out.csv"
SYSTEM "echo === default-derived chisq file ==="
SYSTEM "cat tests/data/tables_save_fpath_out_chisq.csv"
TABLES REGION$*PRODUCT$ /CHISQ /SAVE="tables_save_fpath_out2.csv" /CHISQFILE="tables_save_fpath_custom_chisq.csv"
SYSTEM "echo === /CHISQFILE= override ==="
SYSTEM "cat tests/data/tables_save_fpath_custom_chisq.csv"
FPATH
SYSTEM "rm -f tests/data/tables_save_fpath_out.csv tests/data/tables_save_fpath_out_chisq.csv tests/data/tables_save_fpath_out2.csv tests/data/tables_save_fpath_custom_chisq.csv"
QUIT
