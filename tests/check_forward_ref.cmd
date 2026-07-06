-- Entry-time check: whole-block scope makes forward references legal.  B is
-- referenced before its own LET, but LET B appears later in the same deferred
-- block, so B is "introduced" and the analyzer must NOT flag it as undefined.
-- RUN must complete normally.
USE MOCK
LET A = B + 1
LET B = 2
RUN
