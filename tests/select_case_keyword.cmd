-- F11 (2026-10-19 stress test) regression: design.md spells the multi-way
-- branch "SELECT CASE expr"; it must work like "SELECT expr" + CASE clauses
-- instead of silently swallowing the block.
LET X = 3
SELECT CASE X
  CASE 1 : PRINT "one"
  CASE 3 : PRINT "three"
  OTHERWISE : PRINT "other"
END SELECT
RUN
LET G$ = "B"
SELECT CASE G$
  CASE "A" : PRINT "a"
  CASE "B", "C" : PRINT "b or c"
END SELECT
RUN
QUIT
