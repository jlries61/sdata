-- A terminal comma is always a continuation marker (design.md sec5.4;
-- ADR-072), even in AGGREGATE's own space-separated outvar=func(...) list,
-- which has no comma role of its own.
USE MOCK
AGGREGATE total=SUM(SALARY),
  count=N()
DISPLAY
QUIT
