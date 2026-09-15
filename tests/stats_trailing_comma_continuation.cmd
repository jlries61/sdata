-- A terminal comma is always a continuation marker (design.md sec5.4;
-- ADR-072), even in STATS's own "/flag"-style option loop. A flag-only
-- option (/NOPRINT, no '=' value to opportunistically absorb the comma
-- the way /STATS=<list> would) split from the next option is the sharper
-- edge case here.
USE MOCK
STATS /NOPRINT,
  /STATS=MEAN
QUIT
