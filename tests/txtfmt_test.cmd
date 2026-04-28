-- Test OPTIONS TXTFMT line-ending enforcement in Write_CSV
-- Write CRLF, read back, confirm row count
USE MOCK
OPTIONS TXTFMT CRLF
SAVE "tests/data/txtfmt_crlf.csv"
RUN
USE "tests/data/txtfmt_crlf.csv"
PRINT NAME$
RUN
-- Write LF, read back
USE MOCK
OPTIONS TXTFMT LF
SAVE "tests/data/txtfmt_lf.csv"
RUN
USE "tests/data/txtfmt_lf.csv"
PRINT NAME$
RUN
-- Reset to default
OPTIONS TXTFMT AUTO
QUIT
