-- MINOR-1 (round 1): /TYPES= names a column that a per-dataset KEEP= then
-- removes.  /TYPES= is load-time and KEEP= is a post-load projection, so the
-- declaration applies and the column is dropped afterwards.
USE "tests/data/types_demote.csv" (TYPES="CODE" KEEP=VAL)
NAMES
END
