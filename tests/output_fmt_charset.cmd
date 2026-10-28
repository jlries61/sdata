-- F51 (2026-10-19 stress test) regression: OUTPUT /FMT= (line ending) and
-- /CHARSET= (encoding) apply to the redirected file.
OUTPUT "tests/data/output_fc_crlf.txt" /FMT=CRLF
PRINT "ab"
RUN
OUTPUT
SYSTEM "od -An -c tests/data/output_fc_crlf.txt | head -2"
OUTPUT "tests/data/output_fc_u16.txt" /CHARSET=UTF-16 /FMT=LF
PRINT "hé"
RUN
OUTPUT
SYSTEM "od -An -tx1 tests/data/output_fc_u16.txt | head -2"
SYSTEM "rm -f tests/data/output_fc_crlf.txt tests/data/output_fc_u16.txt"
QUIT
