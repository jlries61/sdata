-- F38/F28 (2026-10-19 stress test) regression: a table with columns but no
-- rows, and REPEAT 0, must run the data step zero times -- no phantom
-- all-missing record, and nothing but the header written by SAVE.

-- Test 1: header-only input.
USE "tests/data/empty_table_hdr.csv"
LET Z = 1
SAVE "tests/data/empty_table_out.csv"
RUN
USE "tests/data/empty_table_out.csv"
NAMES
RUN

-- Test 2: join with no matching keys.
USE "tests/data/join_l.csv", "tests/data/join_r.csv" /BY=K /JOIN
LET Z = 1
RUN

-- Test 3: REPEAT 0.
REPEAT 0
LET X = 1
RUN

-- Test 4: no data at all still gives the single record of a lone RUN.
NEW
LET Y = 1
RUN
DISPLAY

SYSTEM "rm -f tests/data/empty_table_out.csv"
QUIT
