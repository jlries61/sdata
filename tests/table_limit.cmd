-- Test the -m flag (max in-memory table rows).
-- Run with: -m 5
-- Part 1: create 4 rows - within the limit of 5, should succeed.
REPEAT 4
LET X = 1
RUN
-- Part 2: attempt to create 7 rows - exceeds the limit of 5.
NEW
REPEAT 7
LET X = 2
RUN
QUIT
