-- IF= on some but not all specs in a multi-dataset USE (ADR-074/sdata#92
-- -- 02-systems-designer.md Sec7 last item: guards against a stale/reused
-- Include vector leaking from a filtered spec into an unfiltered one in
-- the same statement). use_if_a is filtered to YEARA=2026 (2 rows);
-- use_if_b carries no IF= at all and must show ALL 3 of its rows.
USE "tests/data/use_if_a.csv" (IF=YEARA=2026), "tests/data/use_if_b.csv" /APPEND
PRINT IDA XA IDB YB
RUN
NEW
END
