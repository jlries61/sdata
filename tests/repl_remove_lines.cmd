-- Issue #63 / ADR-054: REMOVE n[-m] is the renamed program-buffer line
-- editor command (was DELETE n[-m]). This is its first real end-to-end
-- REPL integration test -- previously this whole command family
-- (INSERT/LIST/REMOVE) was only exercised via interpreter_unit_test.adb's
-- direct Immediate()/Queue() procedure calls, never through an actual
-- REPL session (the same gap issue #69 closed generally).
--
-- Buffer built as [A=1, A=2, A=3, A=4]; REMOVE 2-3 drops the middle two
-- lines -> [A=1, A=4]; RUN leaves A=4.
LET A = 1
LET A = 2
LET A = 3
LET A = 4
REMOVE 2-3
RUN
PRINT A
RUN
QUIT
