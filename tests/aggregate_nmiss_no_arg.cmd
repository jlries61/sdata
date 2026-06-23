-- AGGREGATE error #3: NMISS requires an argument (only N() may be empty).
USE "tests/data/sample.csv"
AGGREGATE M=NMISS()
QUIT
