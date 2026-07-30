-- issue #66: AGGREGATE placed immediately after REPEAT n (before any LET/SET
-- is queued) must be rejected by the new Repeat_Active guard. With zero
-- deferred statements pending, the pre-existing "AGGREGATE: pending program
-- statements exist" guard (error #10) does NOT fire here -- this exercises
-- the gap that guard left open.
NEW
REPEAT 6
AGGREGATE NREC=N()
QUIT
