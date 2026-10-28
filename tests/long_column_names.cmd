-- F29 (2026-10-19 stress test) regression: a column name longer than the
-- 64-character limit is truncated WITH a warning (it used to be silent).  Here
-- the two long names differ only after the cut, so they collide; the existing
-- duplicate-column warning follows, and only SHORT and one long column remain.
USE "tests/data/long_names.csv"
NAMES
END
