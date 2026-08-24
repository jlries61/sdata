-- ADR-058 regression test (code-review round 1, MAJOR-1): a loop-nested
-- SUBMIT of a given file path that FAILS (here: recursive SUBMIT detected,
-- via a seeded self-referential scratch file) must not permanently mark
-- that path as "already warned". A later, independent loop-nested SUBMIT
-- of the SAME path -- now containing a genuine Declarative statement --
-- is that path's first actually-successful submission and must still get
-- the ADR-056/ADR-058 one-time warning. Requires -k (see .flags): the
-- interpreter must survive the first, failing RUN to reach the second.
USE "tests/data/subscripted.csv"
SYSTEM "cp tests/data/submit_loop_declarative_retry_seed.cmd tests/data/submit_loop_declarative_retry_scratch.cmd"
FOR I = 1 TO 1
SUBMIT "tests/data/submit_loop_declarative_retry_scratch.cmd"
NEXT I
RUN
SYSTEM "cp tests/data/submit_declarative_sub.cmd tests/data/submit_loop_declarative_retry_scratch.cmd"
NEW /PROGRAM
USE "tests/data/subscripted.csv"
FOR I = 1 TO 1
SUBMIT "tests/data/submit_loop_declarative_retry_scratch.cmd"
NEXT I
RUN
QUIT
