-- PB-12: BY is in the ADR-056 declarative-warn set (interpreter.adb) but,
-- until now, no test exercised it specifically -- declarative_in_loop_warn.cmd
-- covers KEEP, mentioning BY only in its comment. Confirms the one-time
-- warning fires exactly once for BY inside a FOR loop, not three times.
-- (BY established only inside a loop can't retroactively populate that same
-- record's FIRST./LAST. temp vars -- Process_One_Record computes those once,
-- before the body runs -- so this test doesn't attempt to read them; that's
-- a separate, structural fact unrelated to this fix.)
NEW
USE MOCK
FOR I = 1 TO 3
  BY ID
NEXT I
PRINT ID
RUN
QUIT
