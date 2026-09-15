-- A terminal comma is always a continuation marker (design.md sec5.4;
-- ADR-072), even in SAVE's own legacy whole-statement "/flag"-style option
-- loop (single spec, no per-target paren block).
OPTIONS SAVEOVERWRT YES
USE MOCK
SAVE "tests/data/save_legacy_trailing_comma_continuation_out.csv" /HEADER=YES,
  /DECIMALS=2
RUN
END
