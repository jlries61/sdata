-- PE-7 code-review MAJOR-1: BREAK's debug sub-prompt (Inspect_PDV) shares the
-- same missing-echo defect as Run_REPL's top-level prompt, reachable under
-- piped/non-tty stdin exactly like Run_REPL's own case -- Interactive_Mode
-- is True for the whole REPL session regardless of tty status, so the debug
-- prompt loop runs and reads real commands (CONTINUE here) via the same
-- unechoed Get_Line pattern PE-7 fixes at the top level. Direct regression
-- guard, written to Standard_Error to match this prompt's own stream.
NEW
REPEAT 2
LET X = RECNO()
BREAK
RUN
CONTINUE
CONTINUE
QUIT
