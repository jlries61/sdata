-- Test 1: saving a dataset where all records are deleted should produce
-- a CSV with a header row.
USE "tests/data/sample.csv"
SAVE "tests/data/bugfix_empty_out.csv"
DELETE
RUN

-- Test 2: reading back a header-only CSV should warn, not error.
USE "tests/data/bugfix_empty_out.csv"
NAMES
RUN

-- Clean up
SYSTEM "rm -f tests/data/bugfix_empty_out.csv"
QUIT
