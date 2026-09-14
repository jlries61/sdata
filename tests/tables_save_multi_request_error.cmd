-- TABLES parser: /SAVE requires exactly one request (ADR-071).
USE "tests/data/freq.csv"
TABLES REGION$ PRODUCT$ /SAVE="tests/data/x.csv"
QUIT
