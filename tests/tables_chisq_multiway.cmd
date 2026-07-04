-- TABLES 3+way /CHISQ: list render then skip-with-warning.
USE "tests/data/freq3.csv"
TABLES REGION$*PRODUCT$*YEAR /CHISQ
QUIT
