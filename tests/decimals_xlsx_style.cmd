USE "tests/data/precision_src.csv"
SAVE "tests/data/style.xlsx" / DECIMALS=2
RUN
SYSTEM 'unzip -p tests/data/style.xlsx xl/styles.xml | grep -o formatCode=\"0.00\"'
SYSTEM 'unzip -p tests/data/style.xlsx xl/worksheets/sheet1.xml | grep -o s=\"1\" | head -1'
SYSTEM "rm -f tests/data/style.xlsx"
QUIT
