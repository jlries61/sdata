-- NOTE (ADR-059): NOTE fires exactly once at its position in program
-- order, never replayed per record inside a REPEAT/RUN body -- like
-- HELP/NAMES, deliberately NOT like ECHO/DIGITS (not added to
-- process_one_record.adb's per-record replay whitelist). A single "NOTE"
-- line here must produce exactly one line of output, not three, even
-- though the surrounding REPEAT body processes 3 records.
SET TOTAL = 0
RUN
REPEAT 3
SET TOTAL = TOTAL + 1
NOTE TOTAL
RUN
QUIT
