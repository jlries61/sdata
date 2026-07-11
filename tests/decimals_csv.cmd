-- SAVE /DECIMALS on CSV: round + trim; default save round-trips.
USE "tests/data/precision_src.csv"
SAVE "tests/data/dc_default.csv"
RUN
SYSTEM "echo === default ==="
SYSTEM "cat tests/data/dc_default.csv"
USE "tests/data/precision_src.csv"
SAVE "tests/data/dc_2.csv" / DECIMALS=2
RUN
SYSTEM "echo === decimals=2 ==="
SYSTEM "cat tests/data/dc_2.csv"
USE "tests/data/precision_src.csv"
SAVE "tests/data/dc_0.csv" / DECIMALS=0
RUN
SYSTEM "echo === decimals=0 ==="
SYSTEM "cat tests/data/dc_0.csv"
SYSTEM "rm -f tests/data/dc_default.csv tests/data/dc_2.csv tests/data/dc_0.csv"
QUIT
