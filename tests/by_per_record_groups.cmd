-- PB-12 (2026-08-13 re-audit): Stmt_BY removed from process_one_record.adb's
-- per-record replay whitelist. BY is Declarative -- dispatched once via the
-- batch walker's immediate pre-scan, before any record runs -- and the
-- redundant per-record redispatch this whitelist entry caused was already a
-- guaranteed no-op after the first record (Already_Established guard,
-- issue #67 / ADR-051), never load-bearing. This locks in FIRST./LAST.
-- group-boundary correctness for a bare, top-level BY in a data-step body
-- with real (non-singleton) groups.
NEW
REPEAT 6
LET G = (RECNO() > 3)
LET VAL = RECNO()
RUN
SORT G
BY G
PRINT RECNO() G VAL FIRST.G LAST.G
RUN
QUIT
