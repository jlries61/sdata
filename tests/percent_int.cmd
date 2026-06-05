-- percent_int: a %-suffixed CSV header loads as an integer column (shared
-- sdata-core behavior, mirroring $ -> string).  Integers print plainly; a
-- non-integer value is truncated toward zero with a warning; a non-numeric
-- value is stored missing with a warning; the load does not abort.
USE "tests/data/percent_int.csv"
PRINT N%
RUN
END
