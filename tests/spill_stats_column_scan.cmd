-- F41 regression: STATS reads one column at a time down all rows.  On a
-- spilled table the segment cache is row-oriented, so that used to reload a
-- segment (every column) at each segment boundary -- hours on a wide file.
-- STATS now reads a whole column in one pass (Table.Prefetch_Column).  With
-- -m 12 (see .flags) and 4 columns a segment is 3 rows, so 40 rows spill into
-- many segments; the numbers below must equal the in-memory results
-- (tests/expected/spill_stats_column_scan.out was generated with -m 0 and
-- diffed against the spilled run).  Covers numeric, integer and character
-- columns with missing values, a whole-table group, and BY groups.
REPEAT 40
LET X = RECNO * 1.5
LET K% = RECNO
LET G = MOD(RECNO, 3)
LET S$ = "r" + STR$(RECNO)
IF MOD(RECNO, 7) = 0 THEN LET X = .
IF MOD(RECNO, 5) = 0 THEN LET S$ = ""
RUN
STATS X K% S$ /STATS=N NMISS
DISPLAY
RUN
NEW
REPEAT 40
LET X = RECNO * 1.5
LET K% = RECNO
LET G = MOD(RECNO, 3)
LET S$ = "r" + STR$(RECNO)
IF MOD(RECNO, 7) = 0 THEN LET X = .
IF MOD(RECNO, 5) = 0 THEN LET S$ = ""
RUN
BY G
STATS X K% /STATS=N MEAN SUM
DISPLAY
RUN
QUIT
