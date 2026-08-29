-- NOTE (ADR-059): a permanent variable buried inside arithmetic is also
-- rejected -- ADR-059's core decision: rejection is NOT limited to a bare
-- top-level reference, since nothing outside AGGREGATE/STATS's own
-- machinery can reduce a permanent variable to a single value.
USE "tests/data/charset_ascii_clean.csv"
NOTE SCORE+1
RUN
QUIT
