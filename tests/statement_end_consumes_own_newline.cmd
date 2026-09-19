-- ADR-080 terminator rule: SELECT scans past separators looking for CASE, so it consumes its
-- own newline; the RUN on the next line must not be mistaken for a same-line follower.
-- (A first prototype of the rule without this exemption failed 44 existing tests.)
USE "tests/data/display_rows.csv"
RUN
SELECT ID > 3
RUN
DISPLAY
QUIT
