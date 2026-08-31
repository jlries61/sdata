-- PE-8's originally-audited repro (ADR-060): a binary operator with
-- nothing following it must fail the whole script, not print a warning
-- and silently continue running the rest of the script as if nothing
-- happened (the exact bug the 2026-08-13 audit found: this used to print
-- the error and still execute USE MOCK / RUN, exiting 0).
USE MOCK
LET X = 1 +
RUN
