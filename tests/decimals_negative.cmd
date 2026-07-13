USE "tests/data/precision_src.csv"
SAVE "tests/data/neg.csv" / DECIMALS=-1
RUN
SYSTEM "rm -f tests/data/neg.csv"
QUIT
