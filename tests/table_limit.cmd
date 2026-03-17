-- Test the -m flag (max in-memory table rows).
-- Run with: -m 5
-- Part 1: create 4 rows - within the limit of 5, should succeed.
LET X = 1
REPEAT 4
RUN
-- Part 2: attempt to create 7 rows - exceeds the limit of 5.
NEW
LET X = 2
REPEAT 7
RUN
QUIT
