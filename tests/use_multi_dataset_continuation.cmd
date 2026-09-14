-- sdata#90: a trailing comma before a newline must survive as the real
-- list separator between USE's dataset specs, not be silently discarded
-- along with the newline it's swallowing.
USE "tests/data/freq.csv",
    "tests/data/freq.csv" /APPEND
NAMES
QUIT
