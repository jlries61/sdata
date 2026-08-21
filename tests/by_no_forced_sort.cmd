-- 2026-08-20 re-audit PD-1 / sdata-core ADR-0013: the audit's own repro
-- (part-d-file-io-execution-model.md) -- three rows, G=1 non-adjacent
-- (separated by a G=2 row in between). Pre-fix, BY physically sorted the
-- table, merging the two G=1 rows into one block (2 blocks total) and
-- silently reordering V from 10,20,30 to 10,30,20. Per design.md sec5.2
-- ("Blocks with same value combination but not consecutive are treated as
-- separate blocks"; "Blocks need not be in sorted order"), the correct
-- result is THREE blocks, and the table's row order must be unchanged.
USE "tests/data/bydata2.csv"
BY G
LET BOG_V = BOG()
LET EOG_V = EOG()
RUN
DISPLAY
QUIT
