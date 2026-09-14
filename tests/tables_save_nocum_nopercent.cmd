-- TABLES /SAVE: /NOCUM and /NOPERCENT drop the same columns from the
-- saved dataset as from the printed report (00-brief.md decision 3,
-- revised) -- not just the console output.
USE "tests/data/freq.csv"
TABLES REGION$ /SAVE="tests/data/tables_save_nocum_out.csv" /NOCUM
SYSTEM "cat tests/data/tables_save_nocum_out.csv"
SYSTEM "rm -f tests/data/tables_save_nocum_out.csv"
TABLES REGION$ /SAVE="tests/data/tables_save_nopct_out.csv" /NOPERCENT
SYSTEM "cat tests/data/tables_save_nopct_out.csv"
SYSTEM "rm -f tests/data/tables_save_nopct_out.csv"
TABLES REGION$ /SAVE="tests/data/tables_save_noboth_out.csv" /NOCUM /NOPERCENT
SYSTEM "cat tests/data/tables_save_noboth_out.csv"
SYSTEM "rm -f tests/data/tables_save_noboth_out.csv"
QUIT
