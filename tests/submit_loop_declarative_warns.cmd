-- ADR-058: SUBMIT inside a loop must produce
-- the same ADR-056 declarative-in-loop warning a directly-inline
-- Declarative statement already gets, instead of today's silence.
-- Single-iteration repro.
USE "tests/data/subscripted.csv"
FOR I = 1 TO 1
SUBMIT "tests/data/submit_declarative_sub.cmd"
NEXT I
RUN
QUIT
