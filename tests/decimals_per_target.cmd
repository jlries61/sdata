-- Per-target DECIMALS; a spreadsheet target keeps full precision.
USE "tests/data/precision_src.csv"
SAVE "tests/data/pt_a.csv" (DECIMALS=1), "tests/data/pt_b.csv" (DECIMALS=3)
RUN
SYSTEM "echo === a: 1dp ==="
SYSTEM "cat tests/data/pt_a.csv"
SYSTEM "echo === b: 3dp ==="
SYSTEM "cat tests/data/pt_b.csv"
SYSTEM "rm -f tests/data/pt_a.csv tests/data/pt_b.csv"
QUIT
