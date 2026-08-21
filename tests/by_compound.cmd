-- Edge case: compound BY key (BY A B).
-- 2026-08-20 re-audit PD-1 / sdata-core ADR-0013: BY no longer sorts, so
-- blocks are consecutive-in-input runs, not consecutive-in-sorted-key runs.
-- (A,B) by record: (1,1)(1,1)(1,2)(2,2)(2,2)(2,1)(1,1) -- exercises an
-- adjacent same-key merge (recs 1-2, and again 4-5), a B-only change (2->3),
-- an A-only change (3->4), a both-change (5->6, 6->7), and critically a
-- NON-adjacent recurrence of an earlier key: record 7's (1,1) matches
-- records 1-2's key but is separated by records 3-6, so it must form its
-- OWN group, not merge back into the first one (design.md sec5.2: "Blocks
-- with same value combination but not consecutive are treated as separate
-- blocks").
REPEAT 7
LET IDX = RECNO()
LET A = IF(IDX <= 3, 1, IF(IDX <= 6, 2, 1))
LET B = IF(IDX <= 2, 1, IF(IDX <= 5, 2, 1))
RUN

BY A B
PRINT A B BOG() EOG()
RUN
QUIT
