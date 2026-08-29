-- PD-8 / ADR-0021: SAVE /CHARSET=ASCII against data containing a non-ASCII
-- character now fails outright (was: warn and write the unconverted bytes
-- anyway, exit 0). Source is loaded without a CHARSET restriction so USE
-- itself succeeds; only the SAVE direction's ASCII check is under test
-- here. Per the systems-designer review, the partial-output-file's exact
-- content/absence is a deliberately out-of-scope, unfixed pre-existing gap
-- (ADR-0021) -- this test asserts only the exit code and error message, not
-- the state of the target file.
USE "tests/data/charset_ascii_bad.csv"
SAVE "tests/data/charset_ascii_save_reject_out.csv" / CHARSET=ASCII
RUN
