-- A terminal comma is always a continuation marker (design.md sec5.4;
-- ADR-072), even in USE's own whole-statement "/flag"-style option loop
-- (distinct from its dataset-list loop, which already uses comma as its
-- native separator and was fixed earlier). A flag-only option (/INTERLEAVE,
-- no '=' value to opportunistically absorb the comma via Parse_Variable_List
-- the way /BY=<list> would) split from the next option is the sharper edge
-- case here -- previously this produced a misleading "/INTERLEAVE and /JOIN
-- require /BY=" error even though /BY=ID was given, because the leftover
-- comma stopped the whole-statement options loop one option early.
USE "tests/data/merge_a.csv", "tests/data/merge_b.csv" /INTERLEAVE,
  /BY=ID
NAMES
QUIT
