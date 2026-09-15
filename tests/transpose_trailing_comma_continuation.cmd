-- A terminal comma is always a continuation marker (design.md sec5.4;
-- ADR-072), even in TRANSPOSE's own "/flag"-style option loop, which has
-- no comma role of its own.
USE MOCK
TRANSPOSE /ID=NAME$,
  /KEEP=SALARY
DISPLAY
QUIT
