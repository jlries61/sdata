-- TABLES /CHISQFILE= overrides the default derived chi-square filename;
-- no file is written at the default-derived name.
USE "tests/data/freq.csv"
TABLES REGION$*PRODUCT$ /CHISQ /SAVE="tests/data/tsc_out.csv" /CHISQFILE="tests/data/tsc_custom.csv"
SYSTEM "echo === custom chisq file ==="
SYSTEM "cat tests/data/tsc_custom.csv"
SYSTEM "echo === default-derived name should not exist ==="
SYSTEM "test -f tests/data/tsc_out_chisq.csv && echo EXISTS || echo ABSENT"
SYSTEM "rm -f tests/data/tsc_out.csv tests/data/tsc_custom.csv"
QUIT
