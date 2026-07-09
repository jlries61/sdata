-- Issue #73 / audit remediation #4: a character ($) or integer (%) variable
-- reference in a SELECT filter must produce an actionable error naming the
-- limitation, not the bare lexer message "unexpected character '$'".
USE "tests/data/sample.csv"
SELECT CATEGORY$ = "A"
RUN
QUIT
