-- A terminal comma is always a continuation marker (design.md sec5.4;
-- ADR-072), even in TABLES's own space/star-separated grammar which has no
-- comma role of its own. Exercises all three split points found in the
-- user-reported script: between the request list and the options, between
-- two space-separated requests, and right after a crossing '*' before its
-- variable.
USE MOCK
TABLES NAME$,
  ID*,
  SALARY,
/list /missing
QUIT
