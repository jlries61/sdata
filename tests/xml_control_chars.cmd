-- F10: XML 1.0 cannot hold the control characters U+0001..U+001F other than
-- TAB, LF and CR, so an XLSX/ODS with one is ill-formed and refused by Excel
-- and LibreOffice (sdata's own reader tolerated it, so a round trip never
-- noticed).  SAVE now removes them and warns once per file; the bytes check
-- below counts what is left in the sheet XML after deleting every legal
-- character: 0 means no control characters were written.  Leading/trailing
-- spaces in an XLSX string must carry xml:space="preserve".
REPEAT 2
LET S$ = "x" + CHR$(1) + "y" + CHR$(31)
IF RECNO = 2 THEN LET S$ = "  padded  "
SAVE "tests/data/xml_ctl.xlsx"
RUN
SAVE "tests/data/xml_ctl.ods"
RUN
SYSTEM "unzip -p tests/data/xml_ctl.xlsx xl/worksheets/sheet1.xml | LC_ALL=C tr -d '\011\012\015\040-\377' | wc -c | tr -d ' '"
SYSTEM "unzip -p tests/data/xml_ctl.ods content.xml | LC_ALL=C tr -d '\011\012\015\040-\377' | wc -c | tr -d ' '"
SYSTEM "unzip -p tests/data/xml_ctl.xlsx xl/worksheets/sheet1.xml | grep -o '<t xml:space=""preserve"">  padded  </t>'"
USE "tests/data/xml_ctl.xlsx"
DISPLAY
RUN
SYSTEM "rm -f tests/data/xml_ctl.xlsx tests/data/xml_ctl.ods"
QUIT
