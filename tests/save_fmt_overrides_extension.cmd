-- F31 (2026-10-19 stress test) regression: an explicit /FMT= overrides the
-- file-name extension (design.md section 4.4) and picks the default
-- extension for a bare name.
USE "tests/data/sample.csv"
SAVE "tests/data/save_fmt_o1.csv" /FMT=OOXML
RUN
SAVE "tests/data/save_fmt_o2" /FMT=ODF
RUN
SYSTEM "head -c 2 tests/data/save_fmt_o1.csv | od -An -c"
SYSTEM "head -c 2 tests/data/save_fmt_o2.ODS | od -An -c"
SYSTEM "rm -f tests/data/save_fmt_o1.csv tests/data/save_fmt_o2.ODS"
QUIT
