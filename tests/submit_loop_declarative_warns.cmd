-- PD-2 (2026-08-13 re-audit) / ADR-058: SUBMIT inside a loop must produce
-- the same ADR-056 declarative-in-loop warning a directly-inline
-- Declarative statement already gets, instead of today's silence. Audit's
-- own repro shape (single iteration).
USE "tests/data/subscripted.csv"
FOR I = 1 TO 1
SUBMIT "tests/data/submit_declarative_sub.cmd"
NEXT I
RUN
QUIT
