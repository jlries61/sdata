-- F04/F52 (2026-10-19 stress test) regression: a built-in function given an
-- argument outside its domain, or a number that does not fit, reports a
-- domain error naming the function/variable -- never Ada runtime text such
-- as "string_fns.adb:55 overflow check failed".  Run with -k so each failing
-- step is reported and the script continues.
REPEAT 1
LET A = ABS(-9223372036854775807 - 1)
RUN
REPEAT 1
LET B$ = CHR$(256)
RUN
REPEAT 1
LET C$ = LEFT$("abc", 1e10)
RUN
REPEAT 1
LET D = ATAN2(0, 0)
RUN
REPEAT 1
LET I% = 2**63
RUN
RSEED 99999999999999999999
QUIT
