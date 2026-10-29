-- F32 regression: an unsupported /CHARSET= or OUTPUT /FMT= is an error.
-- Run with -k so each failing step is reported and the script continues.
USE "tests/data/colon_ranges.csv" /CHARSET=BOGUS
SAVE "invalid_flags_never_written.csv" /CHARSET=BOGUS
OUTPUT "invalid_flags_never_written.txt" /FMT=XYZ
OUTPUT "invalid_flags_never_written.txt" /CHARSET=NOPE
USE "tests/data/colon_ranges.csv" /CHARSET=UTF-8
