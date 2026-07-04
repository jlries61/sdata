-- TABLES parser: unknown slash-option is rejected.
USE "tests/data/freq.csv"
TABLES REGION$ /BOGUS
QUIT
