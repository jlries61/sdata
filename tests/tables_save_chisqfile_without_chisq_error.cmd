-- TABLES parser: /CHISQFILE requires both /SAVE and /CHISQ.
USE "tests/data/freq.csv"
TABLES REGION$ /SAVE="tests/data/x.csv" /CHISQFILE="tests/data/y.csv"
QUIT
